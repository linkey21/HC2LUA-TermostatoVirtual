--[[
%% autostart
--]]

--[[ TermostatoVirtual
	escena
	reguladorPID.lua
	por Manuel Pascual & Antonio Maestre
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local thermostatId = 631  -- id del termostato virtual
local configPanelId = 630  -- id del termostato virtual
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]
-- si se inicia otra escena esta se suicida
if fibaro:countScenes() > 1 then
  fibaro:debug('terminado por nueva actividad')
  fibaro:abort()
end

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='reguladorPID', ver=1, mayor=0, minor=1}
-- ciclos por hora ej. 6 cyclesH = 3600/6 = 1 cliclo cada 600seg.
local cyclesH = 6
-- tiempo mínimo de para accionar calefacción por debajo del cual no se enciende
local antiwindupReset = 0.94
local minTimeAction = 60
local histeresis = 0.64  -- histeresis en grados
local kP = 465          -- Proporcional
local kI = 31           -- Integral
local kD = 62           -- Derivativo
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
  local K = termostatoVirtual.K
  if not K.cyclesH or K.cyclesH == 0 then K.cyclesH = cyclesH end
  if not K.antiwindupReset or K.antiwindupReset == 0 then
    K.antiwindupReset = antiwindupReset
  end
  if not K.minTimeAction or K.minTimeAction == 0 then
    K.minTimeAction = minTimeAction
  end
  if not K.histeresis or K.histeresis == 0 then K.histeresis = histeresis end
  if not K.kP or K.kP == 0 then K.kP = kP end  -- Proporcional
  if not K.kI or K.kI == 0 then K.kI = kI end  -- Integral
  if not K.kD or K.kD == 0 then K.kD = kD end  -- Derivativo
  -- actualizar dispositivo
  termostatoVirtual.K = K
  fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
  -- temperatura en la iteracion anterior se inicia con la temperatura actual
	local lastInput = termostatoVirtual.value
  -- instante hasta próximo ciclo, se inicia con el instante actual
  local cicloStamp = os.time()
  -- intante de cambio de estado de la Caldera, se inicia con el instante actual
  local changePoint = os.time()
  -- valor de la temperatura de consigna, se inicia con la consigna actual
  local setPoint = termostatoVirtual.targetLevel
  -- devilver las variables inicializadas
	return lastInput, cicloStamp, changePoint, setPoint
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
local lastInput, cicloStamp, changePoint, setPoint = Inicializar(thermostatId)

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(thermostatId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

  --[[ Comprobar si el termostato está en modo calibración
  se establece la variable tSeg para controlar tiempo de seguridad máximo que la
  caldera puede estar encendida continnuamente --]]
  local tSeg = os.time() +
   ((3600 / termostatoVirtual['K'].cyclesH) - minTimeAction)
  if termostatoVirtual.mode > 2 then
    -- se detiene el PID hasta que finaliza el calibrado
    cicloStamp = os.time() + 10
    -- si estamos en fase 1 del calibrado, el punto de encendido de la caldera
    -- finaliza después del tiempo de calibrado
    if termostatoVirtual.mode == 3 then
      --[[ se aplica el factor de seguridad para que la caldera no permanezca
      encendida constatemente --]]
      if os.time() <= tSeg then
        changePoint = os.time() + 10
      elseif os.time() <= (tSeg + minTimeAction) then
        changePoint = os.time() - 10
      else
        changePoint = os.time() + 10
        tSeg = os.time() +
         ((3600 / termostatoVirtual['K'].cyclesH) - minTimeAction)
      end
    elseif termostatoVirtual.mode == 4 then -- Fase 2 del calibrado
      changePoint = os.time() - 10
    else -- finaliza el calibrado
      -- poner el termostato en modo AUTO
      termostatoVirtual.mode = 1
      -- actualizar dispositivo
      fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
      -- inicializar el PID
      lastInput, cicloStamp, changePoint, setPoint = Inicializar(thermostatId)
    end
  end

  --[[comprobar cambio en la consigna setPoint
  si cambia la temperatura de consigna, interrupir el ciclo e iniciar un nuevo
  ciclo dejando el estado del PID igual --]]
  if setPoint ~= termostatoVirtual.targetLevel then
    toolKit:log(INFO, 'Cambio del valor de la temperatura de consigna')
    cicloStamp = os.time()
    -- TODO resetear el integrador?
    --termostatoVirtual.PID['acumErr'] = 0
  end

  --[[cálculo PID
  comprobar si se ha cumplido un ciclo para volver a calcular el PID]]
  if os.time() >= cicloStamp then
    -- inicializar el PID
    local PID = termostatoVirtual.PID
    local K = termostatoVirtual.K

    --local PID = {result = 0, newErr = 0, acumErr = acumErr, proporcional = 0,
    -- integral = 0, derivativo = 0}
    -- calcular error
    PID.newErr = termostatoVirtual.targetLevel - termostatoVirtual.value

    -- calcular proporcional
    PID.proporcional = PID.newErr * K.kP
    if PID.proporcional < 0 then
      PID.proporcional = 0
      toolKit:log(INFO, 'proporcional <0')
    end

    -- anti derivative kick usar el inverso de (currentTemp - lastInput) en
    -- lugar de error
    PID.derivativo = ((termostatoVirtual.value - PID.lastInput) * K.kD) * -1

    --[[reset del antiwindup
    si el error no esta comprendido dentro del ámbito de actuación del
    integrador, no se usa el cálculo integral y se acumula error = 0]]
    if math.abs(PID.newErr) > K.antiwindupReset then
    --if PID.newErr <= antiwindupReset then
      -- rectificar el resultado sin integrador
      PID.integral = 0
      PID.acumErr = 0
      toolKit:log(INFO, 'reset antiwindup del integrador ∓'..K.antiwindupReset)

    --[[uso normal del integrador
    se calcula el resultado con el error acumulado anterior y se acumula el
    error actual al error anterior]]
    else
      -- calcular integral
      PID.integral = PID.acumErr * K.kI
      PID.acumErr = PID.acumErr + PID.newErr
    end

    --[[antiwindup del integrador
    si el cálculo integral es mayor que el tiempo de ciclo, se ajusta el
    resultado al tiempo de ciclo y no se acumula el error]]
    if PID.integral > (3600 / K.cyclesH) then
      PID.integral = (3600 / K.cyclesH)
      toolKit:log(INFO, 'antiwindup del integrador > '..(3600 / K.cyclesH))
    end

    -- calcular salida
    PID.result = PID.proporcional + PID.integral + PID.derivativo

    --[[antiwindup de la salida
    si el resultado es mayor que el que el tiempo de ciclo, se ajusta el
    resultado al tiempo de ciclo meno tiempo mínimo y no se acumula el error]]
    if PID.result >= (3600 / K.cyclesH) then
      -- al menos apgar tiempo mínimo
      PID.result = (3600 / K.cyclesH) - K.minTimeAction
      toolKit:log(INFO, 'antiwindup salida > '..(3600 / K.cyclesH))
    elseif PID.result < 0 then
      PID.result = 0
      toolKit:log(INFO, 'antiwindup salida < 0')
    end

    --[[limitador por histeresis
    si error es menor o igual que la histeresis limitar la salida a 0, siempre
    que la tempeatura venga subiendo, no limitar hiteresis de bajada. Resetear
    el error acumulado. Si no hacemos esto tenemos acciones de control de la
    parte integral muy altas debidas a un error acumulado grande cuando estamos
    en histéresis. Eso provoca acciones integrales diferidas muy grandes]]
    if PID.result > 0 and math.abs(PID.newErr) <= K.histeresis then
      PID.acumErr = 0
      if PID.lastInput < termostatoVirtual.value then -- solo de subida
        PID.result = 0
        toolKit:log(INFO, 'histéresis error ∓'..K.histeresis)
      end
    end

    --[[límitador de acción mínima
    si el resultado es menor que el tiempo mínimo de acción, ajustar a 0.
    si se va a encender menos del tiempo mínimo, no encender]]
    if (PID.result <= math.abs(K.minTimeAction)) and (PID.result ~= 0) then
      PID.result = 0
      toolKit:log(INFO, 'tiempo salida ∓'..K.minTimeAction)
      --[[si se va a apgar menos de tiempo mínimo no apagar]]
    elseif PID.result > ((3600 / K.cyclesH) - K.minTimeAction) then
      PID.result = (3600 / K.cyclesH) - K.minTimeAction
    end

    -- informar
    toolKit:log(INFO, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
    PID.integral..', D='..PID.derivativo..', S='..PID.result)

    -- recordar algunas variables para el proximo ciclo SE conservan en el PID
    --result, lastInput, acumErr = PID.result, termostatoVirtual.value,
    --PID.acumErr
    PID.lastInput = termostatoVirtual.value
    -- ajustar temperatura de consigna
    setPoint = termostatoVirtual.targetLevel
    -- ajustar el punto de cambio de estado de la Caldera
    changePoint = os.time() + PID.result
    -- ajustar el nuevo instante de cálculo PID
    cicloStamp = os.time() + (3600 / K.cyclesH)
    -- añadir tiemstamp al PID
    PID.timestamp = os.time(), PID.result

    -- actualizar dispositivo
    termostatoVirtual.PID = PID
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))

    -- informar y decir al termostato que actualice las gráficas
    toolKit:log(INFO, 'Error acumulado: '..PID.acumErr)
    toolKit:log(INFO, '-------------------------------------------------------')
    -- actualizar las gráficas invocando al botón statusButton del termostato
    fibaro:call(configPanelId, "pressButton", "21")
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

  fibaro:sleep(1000)

end
