--[[
%% autostart
--]]

--[[ TermostatoVirtual
	escena
	reguladorPID.lua
	por Manuel Pascual & Antonio Maestre
------------------------------------------------------------------------------]]
-- si se inicia otra escena esta se suicida
if fibaro:countScenes() > 1 then
  _log(DEBUG, 'terminado por nueva actividad')
  fibaro:abort()
end

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local thermostatId = 587  -- id del termostato virtual
local tiempoCiclo = 10   -- tiempo por ciclo de calefacción en segundos
local histeresis = 0.2    -- histeresis en grados
local kP = 150            -- Proporcional
local kI = 20             -- Integral
local kD = 40             -- Derivativo
local thingspeakKey = 'BM0VMH4AF1JZN3QD'
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local intervalo = tiempoCiclo
local release = {name='reguladorPID', ver=1, mayor=0, minor=0}
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
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
      toolKit:log(DEBUG, 'nodeId: '..device.nodeId)
      return device
     end
  end
  -- en cualquier otro caso error
  return false
end

--[[Inicializar()
  Inicializa variables --]]
function Inicializar()
	--if tiempoCiclo < 5 then tiempoCiclo = 5 end -- ciclo mínimo es de 5 min
	local Err = 0 -- Error: diferencia entre consigna y valor actual
	local lastErr = 0 -- Error en la iteracion anterior
	local acumErr = 0 -- Suma error calculado
  local cicloStamp = os.time() -- timestamp hasta próximo ciclo
  local changePoint = os.time() -- punto de cambio de estado de la Caldera
  local inicioCiclo = os.time() -- se inicia el ciclo
  local result = 0 -- resultado salida del PID
	return tiempoCiclo, Err, lastErr, acumErr, cicloStamp, changePoint,
   inicioCiclo, result
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

--[[calculoDerivativo(Err,lastErr,kD)
	Calculo del termino derivativo
------------------------------------------------------------------------------]]
function calculoDerivativo(err,lastErr,kD)
	D = (err - lastErr) * kD -- Termino derivativo
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
  if ((result < tiempo) and (result > (0 - tiempo))) then
    -- si el resultado esta dentro del ambito de histeresis, ajustar histeresis
    if newErr <= histeresis and newErr > 0 then
      -- devolver el error acumulado en el integrador para que el resultado sea
      -- igual a 0 y devolver 0 como resultado
      toolKit:log(INFO, 'Ajuste histéresis')
      return (0 - (P +D)) / kI, 0
    end
    -- devolver el error acumulado en el integrador y el resultado
    return acumErr + newErr, result
  end
  -- si el resultado está fuera del ambito de ciclo de tiempo devolver el error
  -- para el integrador para que el resultado sea igual al ciclo de tiempo y el
  -- rciclo de tiempo como resultado
  toolKit:log(INFO, 'Ajuste antiWindUp')
  return (tiempo - (P + D)) / kI, tiempo
end

--[[calculatePID(currentTemp, setPoint)
(number) currentTemp: temperatura actual de la sonda
(number) setPoint: temperatura de consigna
Calcula utilizando un PID el tiempo de encendido del sistema]]
function calculatePID(currentTemp, setPoint, acumErr, lastErr, tiempo,
  histeresis)
  local newErr, result = 0, 0
  -- calcular error
  newErr = calculoError(currentTemp, setPoint)
  -- calcular proporcional, Integra y derivativo
  P = calculoProporcional(newErr, kP)
  D = calculoDerivativo(newErr, lastErr, kD)
  I = calculoIntegral(acumErr, kI)
  -- obtener el resultado
  result = P + I + D -- Accion total = P+I+D
  -- si el resultado entra en histéresis, calcular el integrador para que el
  -- resultado sea 0
  -- si el resultado sale del rango de ciclo de tiempo calcula el integrador
  -- para que el resultado sea el límete de tiempo.
  acumErr, result = antiWindUpH(result, tiempo, acumErr, newErr, histeresis,
   P, D, kI)
  -- analizar resultado
  toolKit:log(INFO, 'E='..newErr..', P='..P..', I='..I..', D='..D..',S='..
   result)

  -- devolver el resultado, nuevo error y error acumulado
  toolKit:log(DEBUG, 'Cálculo PID: '..result..' '..newErr..' '..acumErr)
  return result, newErr, acumErr

end

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])

-- Inicializar Variables
local tiempoCiclo, Err, lastErr, acumErr, cicloStamp, changePoint, inicioCiclo,
 result = Inicializar()

 -- esperar hasta que exista el termostato
 while not getDevice(thermostatId) do
   toolKit:log(DEBUG, 'Espeando por el termostato')
 end

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(thermostatId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

  --[[comprobar inicio de ciclo--]]
  if (os.time() - inicioCiclo) >= tiempoCiclo then inicioCiclo = os.time() end
  -- if os.time() >= changePoint then inicioCiclo = os.time() end

  --[[cálculo PID]]
  -- comprobar si se ha cumplido un ciclo para volver a calcular el PID
  if os.time() >= cicloStamp then
    -- leer temperatura de la sonda
    currentTemp = termostatoVirtual.value
    -- temperatura de consigna
    setPoint = termostatoVirtual.targetLevel
    -- ajustar el instante de apagado según el cálculo PID y guardar el último
    -- error y error acumulado
    result, lastErr, acumErr = calculatePID(currentTemp, setPoint, acumErr,
     lastErr, tiempoCiclo, histeresis)
    -- ajustar el punto de cambio de estado de la Caldera
    changePoint = inicioCiclo + result
    -- ajustar el nuevo instante de cálculo PID
    cicloStamp = os.time() + intervalo
    -- informar
    toolKit:log(INFO, 'Error acumulado: '..acumErr)
  end

  --[[encendido / apagado]]
  -- si la salida es mayor que el tiempo desde que se encendió, apagar
  if os.time() < changePoint then
    termostatoVirtual.oN = true
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    -- informar
    toolKit:log(DEBUG, 'ON '..(changePoint - os.time()))
  else
    termostatoVirtual.oN = false
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    -- informar
    toolKit:log(DEBUG, 'OFF '..(tiempoCiclo - (os.time() - inicioCiclo)))
  end

 fibaro:sleep(1000)
end
--🌛 🔧  🔥  🔘
