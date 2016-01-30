--[[
%% autostart
--]]

--[[ TermostatoVirtual
	escena
	reguladorPID.lua
	por Manuel Pascual & Antonio Maestre
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local thermostatId = 598  -- id del termostato virtual
local cycleTime = 600     -- tiempo por ciclo de calefacción en segundos
-- tiempo mínimo de para accionar calefacción por debajo del cual no se enciende
local antiwindupReset = 1
local minTimeAction = 60
local histeresis = 0.2    -- histeresis en grados
local kP = 150 * 1.25     -- Proporcional
local kI = 20             -- Integral
local kD = 40             -- Derivativo
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]
-- si se inicia otra escena esta se suicida
if fibaro:countScenes() > 1 then
  fibaro:debug('terminado por nueva actividad')
  fibaro:abort()
end

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='reguladorPID', ver=1, mayor=0, minor=1}

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

	return minTimeAction, Err, lastInput, acumErr, cicloStamp,
   changePoint, setPoint, result
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
 local minTimeAction, Err, lastInput, acumErr, cicloStamp,
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
    -- inicializar el PID
    local PID = {result = 0, newErr = 0, acumErr = acumErr, proporcional = 0,
     integral = 0, derivativo = 0}
    -- calcular error
    PID.newErr = termostatoVirtual.targetLevel - termostatoVirtual.value

    -- calcular proporcional
    PID.proporcional = PID.newErr * kP

    -- anti derivative kick usar (currentTemp - lastInput) en lugar de error
    PID.derivativo = (termostatoVirtual.value - lastInput) * kD

    --[[reset del antiwindup
    si el error no esta comprendido dentro del ámbito de actuación del
    integrador, no se usa el cálculo integral y se acumula error = 0]]
    if math.abs(PID.newErr) > antiwindupReset then
      -- rectificar el resultado sin integrador
      PID.integral = 0
      PID.acumErr = 0
      toolKit:log(INFO, 'reset antiwindup del integrador ∓'..antiwindupReset)

    --[[uso normal del integrador
    se calcula el resultado con el error acumulado anterior y se acumula el
    error actual al error anterior]]
    else
      -- calcular integral
      PID.integral = PID.acumErr * kI
      PID.acumErr = PID.acumErr + PID.newErr
    end

    --[[antiwindup del integrador
    si el cálculo integral es mayor que el tiempo de ciclo, se ajusta el
    resultado al tiempo de ciclo y no se acumula el error]]
    if PID.integral > cycleTime then
      PID.integral = cycleTime
      PID.acumErr = acumErr
      toolKit:log(INFO, 'antiwindup del integrador > '..cycleTime)
    end

    -- calcular salida
    PID.result = PID.proporcional + PID.integral + PID.derivativo

    --[[antiwindup de la salida
    si el resultado es mayor que el que el tiempo de ciclo, se ajusta el
    resultado al tiempo de ciclo y no se acumula el error]]
    if PID.result > cycleTime then
      PID.result = cycleTime
      toolKit:log(INFO, 'antiwindup salida > '..cycleTime)
    elseif PID.result < 0 then
      PID.result = 0
      toolKit:log(INFO, 'antiwindup salida < 0')
    end

    --[[limitador por histeresis
    si error es menor o igual que la histeresis limitar la salida a 0]]
    if PID.result > 0 and math.abs(PID.newErr) < histeresis then
      PID.result = 0
      toolKit:log(INFO, 'histéresis error ∓'..histeresis)
    end

    --[[límitador de acción mínima
    si el resultado es menor que el tiempo mínimo de acción, ajustar a 0]]
    if (PID.result <= math.abs(minTimeAction)) and (PID.result ~= 0) then
      PID.result = 0
      toolKit:log(INFO, 'tiempo salida ∓'..minTimeAction)
    end

    -- informar
    toolKit:log(INFO, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
    PID.integral..', D='..PID.derivativo..', S='..PID.result)

    -- recordar algunas variables para el proximo ciclo
    result, lastInput, acumErr = PID.result, termostatoVirtual.value,
    PID.acumErr
    -- ajustar temperatura de consigna
    setPoint = termostatoVirtual.targetLevel
    -- ajustar el punto de cambio de estado de la Caldera
    changePoint = os.time() + result
    -- ajustar el nuevo instante de cálculo PID
    cicloStamp = os.time() + cycleTime
    -- añadir tiemstamp al PID
    PID.timestamp = os.time(), result
    -- actualizar dispositivo
    termostatoVirtual.PID = PID
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    -- informar y decir al termostato que actualice las gráficas
    toolKit:log(INFO, 'Error acumulado: '..acumErr)
    toolKit:log(INFO, '-------------------------------------------------------')
    -- actualizar las gráficas invocando al botón statusButton del termostato
    fibaro:call(thermostatId, "pressButton", "16")
  end
--[[--------------------------------------------------------------------------]]

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
