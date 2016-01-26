--[[
%% autostart
--]]

--[[ TermostatoVirtual
	escena
	reguladorPID.lua
	por Manuel Pascual & Antonio Maestre
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local thermostatId = 587  -- id del termostato virtual
local cycleTime = 600     -- tiempo por ciclo de calefacción en segundos
-- tiempo mínimo de para accionar calefacción por debajo del cual no se enciende
local minTimeAction = 60
local histeresis = 0.2    -- histeresis en grados
local kP = 150           -- Proporcional
local kI = 20             -- Integral
local kD = 40             -- Derivativo
local thingspeakKey = 'BM0VMH4AF1JZN3QD'
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]
-- si se inicia otra escena esta se suicida
if fibaro:countScenes() > 1 then
  fibaro:debug('terminado por nueva actividad')
  fibaro:abort()
end

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local intervalo = cycleTime
local release = {name='reguladorPID', ver=1, mayor=0, minor=0}

OFF=1;INFO=2;DEBUG=3                -- referencia para el log
nivelLog = INFO                    -- nivel de log
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]

if not toolKit then toolKit = {
  __version = "1.0.0",
  -- log(level, log)
  -- (global) level: nivel de LOG
  -- (string) mensaje: mensaje
  log = (function(self, level, mensaje, ...)
    if not mensaje then mensaje = 'nil' end
    if nivelLog >= level then
      local color = 'yellow'
      if level == INFO then color = 'green' end
      fibaro:debug(string.format(
      '<%s style="color:%s;">%s</%s>', "span", color, mensaje, "span")
      )
    end
  end)
} end

--[[isVariable(varName)
    (string) varName: nombre de la variable global
  comprueba si existe una variable global dada(varName) --]]
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
end

--[[getDevice(nodeId)
    (number) nodeId: número del dispositivo a recuperar de la variable global
  recupera el dispositivo virtual desde la variable global --]]
function getDevice(nodeId)
  -- si  exite la variable global recuperar dispositivo
  local device = isVariable('dev'..nodeId)
  if device and device ~= 'NaN' and device ~= 0 and device ~= '' then
    device = json.decode(device)
    -- si esta iniciado devolver el dispositivo
    if device.nodeId then
      return device
     end
  end
  -- en cualquier otro caso error
  return false
end

--[[Inicializar()
  Inicializa variables --]]
function Inicializar(thermostatId)
  local termostatoVirtual = getDevice(thermostatId)
  -- Error: diferencia entre consigna y valor actual
	local Err = 0
  -- temperatura en la iteracion anterior se inicia con la temperatura actual
	local lastInput = termostatoVirtual.value
  -- Suma error calculado se inicia a 0
	local acumErr = 0
  -- instante hasta próximo ciclo, se inicia con el instante actual
  local cicloStamp = os.time()
  -- intante de cambio de estado de la Caldera, se inicia con el instante actual
  local changePoint = os.time()
  -- resultado salida del PID. se inicia a 0
  local result = 0
  -- valor de la temperatura de consigna, se inicia con la consigna actual
  local setPoint = termostatoVirtual.targetLevel

	return cycleTime, minTimeAction, Err, lastInput, acumErr, cicloStamp,
   changePoint, setPoint, result
end

--[[calculoError(Actual, Consigna)
	Calculo del error diferencia entre temperatura Actual y Consigna
------------------------------------------------------------------------------]]
function calculoError(currentTemp, Consigna)
	return tonumber(Consigna) - tonumber(currentTemp)
end

--[[calculoProporcional(Err,kP)
	Calculo del termino proporcional
------------------------------------------------------------------------------]]
function calculoProporcional(err, kP)
	P = err * kP -- Termino proporcional
	return P
end

--[[calculoDerivativo(dInput ,kD)
	Calculo del termino derivativo
------------------------------------------------------------------------------]]
function calculoDerivativo(dInput, kD)
	D = dInput * kD -- Termino derivativo
	return D
end

--[[calculoIntegral(acumErr, kI)
	Calculo del termino integral
------------------------------------------------------------------------------]]
function calculoIntegral(acumErr, kI)
	I = acumErr * kI -- Termino integral
	return I
end

--[[antiWindUpH(result, tiempo, acumErr, newErr, histeresis, P, D, kI) --]]
function antiWindUpH(result, tiempo, acumErr, newErr, histeresis, P, D, kI)
  -- si el resultado está dentro del anbito de tiempo de ciclo, no hay windUp
  if ((result <= tiempo) and (result > 0)) then
    -- si la temperatura esta dentro del ambito de histeresis, ajustar a 0
    if (newErr <= histeresis and newErr > 0 )then
      toolKit:log(INFO, 'Ajuste por histéresis: '..newErr..' Salida: '..result
      ..' = 0')
      -- devolver el error para acumular en el integrador para que el resultado
      -- sea igual a 0 y devolver 0 como resultado
      return (0 - (P + D)) / kI, 0
    end
    -- si el resultadoes menor que el tiempo mínimo de acción, ajustar a 0
    if result <= minTimeAction then
      toolKit:log(INFO, 'Ajuste por tiempo mínimo: '..result..'/'..minTimeAction
      ..' Salida: '..result..' = 0')
      -- devolver el error para acumular en el integrador para que el resultado
      -- sea igual a 0 y devolver 0 como resultado
      return (0 - (P + D)) / kI, 0
    end
    -- devolver el error acumulado en el integrador y el resultado
    return acumErr + newErr, result
  end
  -- si el resultado es mayor que el ciclo de tiempo, devolver al integrador el
  -- valor necesario para que el resultado sea igual al ciclo de tiempo y como
  -- resultado devolver el ciclo de tiempo.
  if result > 0 then
    toolKit:log(INFO, 'Ajuste por salida mayor que ciclo: '..' Salida: '..
     result..' = '..tiempo)
     -- devolver el error para acumular en el integrador para que el resultado
     -- sea igual a tiempo de cliclo y devolver tiempo de cliclo como resultado
    return (tiempo - (P + D)) / kI, tiempo
  end
  -- si el resultado es menor que el ciclo de tiempo devolver 0 como valor para
  -- el integrador y 0 como resultado.
  toolKit:log(INFO, 'Ajuste por resultado menor que 0: '..' Salida: '..result
   ..' = 0')
  return 0, 0
end

--[[calculatePID(currentTemp, setPoint)
(number) currentTemp: temperatura actual de la sonda
(number) setPoint: temperatura de consigna
Calcula utilizando un PID el tiempo de encendido del sistema]]
function calculatePID(currentTemp, setPoint, acumErr, lastInput, tiempo,
  histeresis)
  local PID = {result = 0, newErr = 0, acumErr = acumErr, proporcional = 0,
   integral = 0, derivativo = 0}
  -- calcular error
  PID.newErr = calculoError(currentTemp, setPoint)
  -- calcular proporcional, Integral y derivativo
  PID.proporcional = calculoProporcional(PID.newErr , kP)
  -- anti derivative kick currentTemp - lastInput
  PID.derivativo = calculoDerivativo(currentTemp - lastInput, kD)
  PID.integral = calculoIntegral(PID.acumErr, kI)
  -- obtener el resultado
  PID.result = PID.proporcional + PID.integral + PID.derivativo
  -- antiWindUp/histeresis
  -- si el resultado entra en histéresis, calcular el integrador para que el
  -- resultado sea 0, solo si la temperatura viene de subida
  if (currentTemp - lastInput) <= 0 then histeresis = 0 end
  -- si el resultado sale del rango de ciclo de tiempo calcula el integrador
  -- para que el resultado sea el límete de tiempo.
  PID.acumErr, PID.result = antiWindUpH(PID.result, tiempo, PID.acumErr,
   PID.newErr, histeresis, PID.proporcional, PID.derivativo, kI)
  -- analizar resultado
  toolKit:log(INFO, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
  PID.integral..', D='..PID.derivativo..', S='..PID.result)
  -- devolver el resultado del PID
  return PID
end

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])
toolKit:log(INFO, '-------------------------------------------------------')

 -- esperar hasta que exista el termostato
 while not getDevice(thermostatId) do
   toolKit:log(DEBUG, 'Espeando por el termostato')
 end

 -- Inicializar Variables
 local cycleTime, minTimeAction, Err, lastInput, acumErr, cicloStamp,
  changePoint, setPoint, result = Inicializar(thermostatId)

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(thermostatId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

  --[[comprobar cambio en la consigna setPoint--]]
  -- si cambia la temperatura de consigna, interrupir el ciclo e iniciar un
  -- nuevo ciclo dejando el estado del PID igual
  if setPoint ~= termostatoVirtual.targetLevel then
    toolKit:log(INFO, 'Cambio del valor de la temperatura de consigna')
    cicloStamp = os.time()
  end

  --[[cálculo PID]]
  -- comprobar si se ha cumplido un ciclo para volver a calcular el PID
  if os.time() >= cicloStamp then
    -- ajustar el instante de apagado según el cálculo PID y guardar el último
    -- error y error acumulado
    local PID = calculatePID(termostatoVirtual.value,
     termostatoVirtual.targetLevel, acumErr, lastInput, cycleTime, histeresis)
     -- recordar algunas variables para el proximo ciclo
     result, lastInput, acumErr = PID.result, termostatoVirtual.value,
     PID.acumErr
    -- ajustar temperatura de consigna
    setPoint = termostatoVirtual.targetLevel
    -- ajustar el punto de cambio de estado de la Caldera
    changePoint = os.time() + result
    -- ajustar el nuevo instante de cálculo PID
    cicloStamp = os.time() + cycleTime
    -- guardar el último instante en el que se calcula el PID
    PID.timestamp = os.time()
    termostatoVirtual.PID = PID
    -- actualizar dispositivo
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    -- informar
    toolKit:log(INFO, 'Error acumulado: '..acumErr)
    toolKit:log(INFO, '-------------------------------------------------------')
  end

  --[[encendido / apagado]]
  -- si no se ha llegado al punto de cambio encender
  if os.time() < changePoint then
    if not termostatoVirtual.oN then
      termostatoVirtual.oN = true
      -- actualizar dispositivo
      fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    end
  else -- si la salida es mayor que el tiempo desde que se encendió, apagar
    if termostatoVirtual.oN then
      termostatoVirtual.oN = false
      -- actualizar dispositivo
      fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    end
  end

end
