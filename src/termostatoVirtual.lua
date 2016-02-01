--[[
%% autostart
--]]

--[[ TermostatoVirtual
	escena
	termostatoVirtual.lua
	por Manuel Pascual & Antonio Maestre
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local iconON = 1067
local iconOFF = 1066
local thermostatId = 608  -- id del termostato virtual
local cycleTime = 600     -- tiempo por ciclo de calefacción en segundos
-- tiempo mínimo de para accionar calefacción por debajo del cual no se enciende
local antiwindupReset = 0.5
local minTimeAction = 60
local histeresis = 0.2    -- histeresis en grados
local kP = 225     -- Proporcional
local kI = 20             -- Integral
local kD = 40             -- Derivativo
-- función para obtener la temperatura de la sonda virtual, escribir a
-- continuación de 'return' el código o expresión para obtener la temperatura
local virtualProbe = function (self, ...)
  local t = fibaro:getValue(389, 'value')
  return math.floor((t - (30 / t)) * 100) / 100
end
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]
-- si se inicia otra escena esta se suicida
if fibaro:countScenes() > 1 then
  fibaro:debug('terminado por nueva actividad')
  fibaro:abort()
end

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='reguladorPID', ver=1, mayor=0, minor=1}
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
if not oN then oN = true end
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

--[[getPanel(roomId)
    (number) nodeId: número del dispositivo a almacenar en la variable global
  devuelve el panel de calefacción que controla la habitación donde se encuentra
  el disposito virtual con identificador nodeId --]]
function getPanel(roomId)
  toolKit:log(DEBUG, 'roomId: '..roomId)
  -- obtener paneles de temperatura
  if not HC2 then HC2 = Net.FHttp("127.0.0.1", 11111) end
  response ,status, errorCode = HC2:GET("/api/panels/heating")
  -- recorrer la tabla de paneles y buscar si alguno controla esta habitación
  local panels = json.decode(response)
  for pKey, pValue in pairs(panels) do
    toolKit:log(DEBUG, 'Panel: '..pValue.id)
    -- obtener panel
    if not HC2 then HC2 = Net.FHttp("127.0.0.1", 11111) end
    response ,status, errorCode = HC2:GET("/api/panels/heating/"..pValue.id)
    local panel = json.decode(response)
    local rooms = panel['properties'].rooms
    -- recorrer las habitaciones de cada panel
    for rKey, rValue in pairs(rooms) do
      toolKit:log(DEBUG, 'Room: '..rValue)
      if rValue == roomId then return panel end
    end
  end
  return false
end

--[[getTargetLevel(panel)
    (table) panel: tabla que representa un panel de temperatura
  devuelve la temperatura de consigna desde panel indicado
--]]
function getTargetLevel(panel)
  -- obtener propiedades del panel
  local properties = panel.properties

  -- si vacationTemperature ~= 0 devolver "vacationTemperature"
  if properties.vacationTemperature ~= 0 then
    return properties.vacationTemperature
  end

  -- si handTimestamp >= os.time() devolver "handTemperature"
  if properties.handTimestamp >= os.time() then
    return properties.handTemperature
  end

  -- en otro caso devolver "temperature"
  -- obtener dia de la semana de hoy
  local dow = string.lower(tostring(os.date('%A')))
  toolKit:log(DEBUG, 'Hoy es: '..dow)
  -- obtener la tabla con propiedades del día de la semana
  local todayTab = properties[dow]

  -- obtenr día de la semana de fue ayer
  dow = string.lower(tostring(os.date('%A', os.time() - 24*60*60 )))
  toolKit:log(DEBUG, 'Ayer fue: '..dow)
  -- obtener tabla con propiedades de ayer
  local yesterdayTab = properties[dow]
  -- obtener la temperatura de la noche de ayer para poder usarla como posible
  -- temperatura, si la hora actual es anteriror a la de la mañana del panel,
  -- hay que tomar la de la noche del día anteriror.
  local temperatura = yesterdayTab['night'].temperature
  toolKit:log(DEBUG, 'Temperatura ayer noche: '..temperatura)

  -- las partes en las que divide el día el panel
  local states = {'morning', 'day', 'evening', 'night'}
  local year, month, day = os.date('%Y'), os.date('%m'), os.date('%d')
  toolKit:log(DEBUG, os.time())
  -- inicialmete tomar como temperatura la última temperatura del día anteriror.
  -- recorrer los diferentes partes en las que divide el día en panel y comparar
  -- el timestamp de cada una de ellas con el timestamp actual, si el actual es
  -- mayor o igual se va tomando la temperatura de esa parte.
  for key, value in pairs(states) do
    local hour = todayTab[value].hour
    local min = todayTab[value].minute
    toolKit:log(DEBUG, hour..':'..min)
    local timestamp =
     os.time{year = year, month = month, day = day, hour = hour, min = min}
    toolKit:log(DEBUG, timestamp)
    if os.time() >= timestamp then
      temperatura = todayTab[value].temperature
    else
      break
    end
  end
  -- devolver la temperatura que corresponde en el panel en este momento
  return temperatura
end

--[[setActuador(actuatorId, actuador)
  --]]
function setActuador(actuatorId, actuador)
  -- si el actuador no está en modo mantenimiento
  if actuatorId and actuatorId ~= 0 then
    -- comprobar estado actual
    --local actuatorState = fibaro:getValue(actuatorId, 'value')
    local actuatorState = fibaro:getValue(actuatorId, 'mode') -- 1=OFF 0=ON
    -- si hay que encender y esta apagado
    if actuador and actuatorState == '0' then
      -- encender
      --fibaro:call(actuatorId, 'turnOn')
      fibaro:call(actuatorId, "setMode", 1)
    end
    -- si hay que apagar y está encendido
    if not actuador and actuatorState == '1' then
      --fibaro:call(actuatorId, 'turnOff')
      fibaro:call(actuatorId, "setMode", 0)
    end
  end
end

--[[Inicializar()
  Inicializa variables --]]
function Inicializar(thermostatId)
  local virtualThermostat = getDevice(thermostatId)
  -- temperatura en la iteracion anterior se inicia con la temperatura actual
	local lastInput = virtualThermostat.value
  -- instante hasta próximo ciclo, se inicia con el instante actual
  local cicloStamp = os.time()
  -- intante de cambio de estado de la Caldera, se inicia con el instante actual
  local changePoint = os.time()
  -- valor de la temperatura de consigna, se inicia con la consigna actual
  local setPoint = virtualThermostat.targetLevel
  -- devilver las variables inicializadas
	return lastInput, cicloStamp, changePoint, setPoint
end

--[[updateVirtualDev()
  (table) virtualThermostat: tabla que representa el termostato virtual
  ]]
function updateVirtualDev(virtualThermostat)
  --[[Panel]]
  -- obtener el panel
  local panel = getPanel(fibaro:getRoomID(virtualThermostat.nodeId))
  if panel then
    toolKit:log(DEBUG, 'Nombre panel: '..panel.name)
    -- actualizar dispositivo
    virtualThermostat.panelId = panel.id
  end

  --[[temperarura actual]]
  -- si hay sonda declarada obtener la temperatura
  if virtualThermostat.probeId and virtualThermostat.probeId ~= 0 then
    virtualThermostat.value =
     tonumber(fibaro:getValue(virtualThermostat.probeId, 'value'))
  elseif virtualThermostat.probeId == 0 then
    -- si la sonda es virtual
    virtualThermostat.value = virtualProbe()
  end

  --[[temperarura de consigna]]
  -- comparar timestamp con os.time() y comprobar mode virtualThermostat.timestamp
  if (virtualThermostat.timestamp < os.time()) and virtualThermostat.mode ~= 0
   then
    -- si es menor y status no es OFF, tomar temperatura del panel
    virtualThermostat.targetLevel = getTargetLevel(panel)
    toolKit:log(DEBUG, 'Temperatura consigna: '..virtualThermostat.targetLevel
     ..'ºC')
  end

  --[[tiempo de protección]]
  -- si el modo es no es OFF
  if virtualThermostat.mode ~= 0 then
    local shadowTime = virtualThermostat.timestamp - os.time()
    if shadowTime <= 0 then
      shadowTime = 0
      -- actualizar estado del dispositivo
      virtualThermostat.mode = 1
    else
      shadowTime = shadowTime / 60
      -- actualizar estado del dispositivo
      virtualThermostat.mode = 2
    end
  end

  return virtualThermostat
end

--[[updateVirtualLayout(virtualThermostat)
  (table) virtualThermostat: tabla que representa el termostato virtual
]]
function updateVirtualLayout(virtualThermostat)
  local onOff = ' _'
  local icono = iconOFF
  local targetLevel = tonumber(getDevice(virtualThermostat.nodeId).targetLevel)
  local value = tonumber(getDevice(virtualThermostat.nodeId).value)
  if virtualThermostat.oN then
    onOff = ' 🔥'
    icono = iconON
  end
  targetLevel = string.format('%.2f', targetLevel)
  value = string.format('%.2f', value)
  -- actualizar etiqueta
  fibaro:call(thermostatId, "setProperty", "ui.actualConsigna.value",
   value..'ºC / '..targetLevel..'ºC'..onOff)
  -- actualizar icono
  fibaro:call(thermostatId, 'setProperty', "currentIcon", icono)
  -- actualizar etiqueda de modo de funcionamiento "mode""
  toolKit:log(DEBUG, 'Modo: '..mode[virtualThermostat.mode])
  fibaro:call(thermostatId, "setProperty", "ui.modeLabel.value",
   mode[virtualThermostat.mode])
   -- actualizar etiqueta de tiempo
  local minText = {}; local timeLabel = '06h 00m'
  minText[0]   = '00h 00m'; minText[15]  = '00h 15m'; minText[30]  = '00h 30m'
  minText[45]  = '00h 45m'; minText[60]  = '01h 00m'; minText[75]  = '01h 15m'
  minText[90]  = '01h 30m'; minText[105] = '01h 45m'; minText[120] = '02h 00m'
  minText[135] = '02h 15m'; minText[150] = '02h 30m'; minText[165] = '02h 45m'
  minText[180] = '03h 00m'; minText[195] = '03h 15m'; minText[210] = '03h 30m'
  minText[225] = '03h 45m'; minText[240] = '04h 00m'; minText[255] = '04h 15m'
  minText[270] = '04h 30m'; minText[285] = '04h 45m'; minText[300] = '05h 00m'
  minText[315] = '05h 15m'; minText[330] = '05h 30m'; minText[345] = '05h 45m'
  minText[360] = '06h 00m'
  for value = 360, 0, -15 do
    if shadowTime <= value then
      timeLabel = minText[value]
    else
      break
    end
  end
  -- actualizar etiqueta de tiempo
  fibaro:call(thermostatId, "setProperty", "ui.timeLabel.value", timeLabel)
end

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])
toolKit:log(INFO, '-------------------------------------------------------')

-- Inicializar Variables
local lastInput, cicloStamp, changePoint, setPoint = Inicializar(thermostatId)

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  ---- recuperar o iniciar dispositivo y actualizar valores
  local virtualThermostat = updateVirtualDev(getDevice(thermostatId))
  -- guardar dispositivo en variable global
  fibaro:setGlobal('dev'..thermostatId, json.encode(virtualThermostat))
  -- actualizar icono y etiquetas
  updateVirtualLayout(virtualThermostat)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(virtualThermostat))

  --[[comprobar cambio en la consigna setPoint
  si cambia la temperatura de consigna, interrupir el ciclo e iniciar un nuevo
  ciclo dejando el estado del PID igual]]
  if setPoint ~= virtualThermostat.targetLevel then
    toolKit:log(INFO, 'Cambio del valor de la temperatura de consigna')
    cicloStamp = os.time()
    -- TODO resetear el integrador?
    --virtualThermostat.PID['acumErr'] = 0
  end

  --[[cálculo PID
  comprobar si se ha cumplido un ciclo para volver a calcular el PID]]
  if os.time() >= cicloStamp then
    -- inicializar el PID
    local PID = virtualThermostat.PID
    --local PID = {result = 0, newErr = 0, acumErr = acumErr, proporcional = 0,
    -- integral = 0, derivativo = 0}
    -- calcular error
    PID.newErr = virtualThermostat.targetLevel - virtualThermostat.value

    -- calcular proporcional
    PID.proporcional = PID.newErr * kP

    -- anti derivative kick usar el inverso de (currentTemp - lastInput) en
    -- lugar de error
    PID.derivativo = ((virtualThermostat.value - lastInput) * kD) * -1

    --[[reset del antiwindup
    si el error no esta comprendido dentro del ámbito de actuación del
    integrador, no se usa el cálculo integral y se acumula error = 0]]
    --if math.abs(PID.newErr) > antiwindupReset then
    if PID.newErr <= antiwindupReset then
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
    if PID.result > 0 and math.abs(PID.newErr) <= histeresis then
      PID.result = 0
      toolKit:log(INFO, 'histéresis error ∓'..histeresis)
    end

    --[[límitador de acción mínima
    si el resultado es menor que el tiempo mínimo de acción, ajustar a 0.
    si se va a encender menos del tiemp mínimo, no encender]]
    if (PID.result <= math.abs(minTimeAction)) and (PID.result ~= 0) then
      PID.result = 0
      toolKit:log(INFO, 'tiempo salida ∓'..minTimeAction)
    end
    --[[si se va a apgar menos de tiempo mínimo no apagar]]
    -- elseif PID.result > (cycleTime - minTimeAction) then PID.result = cycleTime

    -- informar
    toolKit:log(INFO, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
    PID.integral..', D='..PID.derivativo..', S='..PID.result)

    -- recordar algunas variables para el proximo ciclo SE conservan en el PID
    --result, lastInput, acumErr = PID.result, virtualThermostat.value,
    --PID.acumErr
    -- ajustar temperatura de consigna
    setPoint = virtualThermostat.targetLevel
    -- ajustar el punto de cambio de estado de la Caldera
    changePoint = os.time() + PID.result
    -- ajustar el nuevo instante de cálculo PID
    cicloStamp = os.time() + cycleTime
    -- añadir tiemstamp al PID
    PID.timestamp = os.time(), PID.result
    -- actualizar dispositivo
    virtualThermostat.PID = PID
    fibaro:setGlobal('dev'..thermostatId, json.encode(virtualThermostat))
    -- informar y decir al termostato que actualice las gráficas
    toolKit:log(INFO, 'Error acumulado: '..PID.acumErr)
    toolKit:log(INFO, '-------------------------------------------------------')
    -- actualizar las gráficas invocando al botón statusButton del termostato
    fibaro:call(thermostatId, "pressButton", "16")
  end
--[[--------------------------------------------------------------------------]]

  --[[encendido / apagado]]
  -- si no se ha llegado al punto de cambio encender
  if os.time() < changePoint then
    if not virtualThermostat.oN then
      virtualThermostat.oN = true
      -- actualizar dispositivo
      fibaro:setGlobal('dev'..thermostatId, json.encode(virtualThermostat))
      -- informar
      toolKit:log(INFO, 'ON')
      -- actuar sobre el actuador si es preciso
      setActuador(termostatoVirtual.actuatorId, true)
    end
  else -- si la salida es mayor que el tiempo desde que se encendió, apagar
    if virtualThermostat.oN then
      virtualThermostat.oN = false
      -- actualizar dispositivo
      fibaro:setGlobal('dev'..thermostatId, json.encode(virtualThermostat))
      -- informar
      toolKit:log(INFO, 'OFF')
      -- actuar sobre el actuador si es preciso
      setActuador(termostatoVirtual.actuatorId, false)
    end
  end

end
