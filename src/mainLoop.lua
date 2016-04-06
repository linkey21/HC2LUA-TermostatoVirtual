--[[ termostat.linkey.es
	Dispositivo virtual
	mainLoop.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
-- id de los iconos ON OFF
local iconON = 1067
local iconOFF = 1066
local thingspeakKey = ''

-- función para obtener la temperatura de la sonda virtual, escribir a
-- continuación de 'return' el código o expresión para obtener la temperatura
local virtualProbe = function (self, ...)
  local t = fibaro:getValue(389, 'value')
  return math.floor((t - ((41 - t) / t)) * 100) / 100
end
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='termostatoVirtual', ver=2, mayor=0, minor=0}
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
mode[3]='CALIBRADO_F1'; mode[4]='CALIBRADO_F2'; mode[5]='CALIBRADO_FIN'
OFF=1;INFO=2;DEBUG=3                -- referencia para el log
nivelLog = INFO                    -- nivel de log
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]

--[[toolKit
Conjunto de funciones para compartir en varios proyectos --]]
if not toolKit then toolKit = {
  __version = "1.0.1",
  -- log(level, log)
  -- (global) level: nivel de LOG
  -- (string) mensaje: mensaje
  log = (
  function(self, level, mensaje, ...)
    if not mensaje then mensaje = 'nil' end
    if nivelLog >= level then
      local color = 'yellow'
      if level == INFO then color = 'green' end
      fibaro:debug(string.format(
      '<%s style="color:%s;">%s</%s>', "span", color, mensaje, "span")
      )
    end
  end),
  calculatePID = (
  --[[calculatePID()
    (table) PID:  tabla que representa el estado actual del PID
    Calcula el PID y lo devuelve una tabla que lo representa
    Tabla PID:
    {result = 0, newErr = 0, acumErr = 0, proporcional = 0,
    integral = 0, derivativo = 0, lastInput = 0, value = 0, targetLevel = 0,
    kP = 250, kI = 50, kD = 25, cyclesH = 12, antiwindupReset = 1, tuneTime = 0,
    checkPoint = 0, changePoint = 0, minTimeAction = 30, secureTimeAction = 0,
    histeresis = 0.1}
    --]]
  function(self, PID, ...)
    toolKit:log(INFO, '----- calculatePID v2.0 -----------------------------')
    -- calcular error
    PID.newErr = PID.targetLevel - PID.value

    -- calcular proporcional y si es negativo dejarlo a cero
    PID.proporcional = PID.newErr * PID.kP
    if PID.proporcional < 0 then
      PID.proporcional = 0
      toolKit:log(INFO, 'proporcional < 0')
    end

    -- anti derivative kick usar el inverso de (currentTemp - lastInput) en
    -- lugar de error
    PID.derivativo = ((PID.value - PID.lastInput) * PID.kD) * - 1

    --[[reset del antiwindup
    si el error no esta comprendido dentro del ámbito de actuación del
    integrador, no se usa el cálculo integral y se acumula error = 0]]
    if math.abs(PID.newErr) > PID.antiwindupReset then
      PID.integral = 0
      PID.acumErr = 0
      toolKit:log(INFO, 'reset antiwindup del integrador ∓'..PID.antiwindupReset)

    --[[uso normal del integrador
    se calcula el resultado con el error acumulado anterior y se acumula el
    error actual al error anterior]]
    else
      -- calcular integral
      PID.integral = PID.acumErr * PID.kI
      PID.acumErr = PID.acumErr + PID.newErr
    end

    --[[antiwindup del integrador
    si el cálculo integral es mayor que el tiempo de ciclo, se ajusta el
    resultado al tiempo de ciclo y no se acumula el error]]
    if PID.integral > (3600 / PID.cyclesH) then
      PID.integral = (3600 / PID.cyclesH)
      toolKit:log(INFO, 'antiwindup del integrador > '..(3600 / PID.cyclesH))
    end

    -- calcular salida
    PID.result = PID.proporcional + PID.integral + PID.derivativo

    --[[antiwindup de la salida
    si el resultado es mayor que el que el tiempo de ciclo, se ajusta el
    resultado al tiempo de ciclo menos tiempo de seguridad y no se acumula el
    error --]]
    if PID.result >= (3600 / PID.cyclesH) then
      -- al menos apgar tiempo mínimo
      PID.result = (3600 / PID.cyclesH) - PID.secureTimeAction
      toolKit:log(INFO, 'antiwindup salida > '..(3600 / PID.cyclesH) -
       PID.secureTimeAction)
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
    if PID.result > 0 and math.abs(PID.newErr) <= PID.histeresis then
      PID.acumErr = 0
      if PID.lastInput < PID.value then -- solo de subida
        PID.result = 0
        toolKit:log(INFO, 'histéresis error ∓'..PID.histeresis)
      end
    end

    --[[límitador de acción mínima
    si el resultado es menor que el tiempo mínimo de acción, ajustar a 0.
    si se va a encender menos del tiempo mínimo, no encender]]
    if (PID.result <= math.abs(PID.minTimeAction)) and (PID.result ~= 0) then
      PID.result = 0
      toolKit:log(INFO, 'tiempo salida ∓'..PID.minTimeAction)
      --[[si se va a apgar menos de tiempo de seguridad no apagar]]
    elseif PID.result > ((3600 / PID.cyclesH) - PID.secureTimeAction) then
      PID.result = (3600 / PID.cyclesH) - PID.secureTimeAction
    end

    -- informar
    toolKit:log(INFO, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
    PID.integral..', D='..PID.derivativo..', S='..PID.result)

    -- recordar algunas variables para el proximo ciclo SE conservan en el PID
    --result, lastInput, acumErr = PID.result, termostatoVirtual.value,
    --PID.acumErr
    PID.lastInput = PID.value
    -- ajustar el punto de cambio de estado de la Caldera
    PID.changePoint = os.time() + PID.result
    -- ajustar el punto de próximo cálculo
    PID.checkPoint = os.time() + (3600 / PID.cyclesH)
    -- añadir tiemstamp al PID
    PID.timestamp = os.time()

    -- informar
    toolKit:log(INFO, 'Error acumulado: '..PID.acumErr)
    toolKit:log(INFO, '-------------------------------------------------------')

    -- devolver PID
    return PID
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

--[[resetDevice(nodeId)
    (number) nodeId: número del dispositivo a almacenar en la variable global
  crea una varaible global para almacenar la tabla que representa el dispositivo
  y lo inicializa. --]]
function resetDevice(nodeId)
  -- si no exite la variable global
  if not isVariable('dev'..nodeId) then
    -- intentar crear la variableGlobal
    local json = '{"name":"'..'dev'..nodeId..'", "isEnum":0}'
    if not HC2 then HC2 = Net.FHttp("127.0.0.1", 11111) end
    HC2:POST("/api/globalVariables", json)
    fibaro:sleep(1000)
    -- comprobar que se ha creado la variableGlobal
    if not isVariable('dev'..nodeId) then
      toolKit:log(DEBUG, 'No se pudo declarar variable global '..'dev'..nodeId)
      fibaro:abort()
    end
  end
  -- crear tabla vacía para dispositivo
  -- el dispositivo tiene un PID
  local PID = {result = 0, newErr = 0, acumErr = 0, proporcional = 0,
   integral = 0, derivativo = 0, lastInput = 0, value = 0, targetLevel = 0,
   kP = 400, kI = 50, kD = 75, cyclesH = 6, antiwindupReset = 0.8, tuneTime = 0,
   checkPoint = 0, changePoint = 0, minTimeAction = 30, secureTimeAction = 15,
   histeresis = 0.2}

  local actuator = {id = 0, name = '', onFunction = '', offFunction = '',
   statusPropertie = '', maintenance = true}

  local termostatoVirtual = {PID = PID, actuator = actuator, nodeId = nodeId,
   panelId = 0, probeId = 0, targetLevel = 0, value = 0, mode = 1,
   timestamp = os.time(), oN = false}
  -- guardar la tabla en la variable global
  fibaro:setGlobal('dev'..nodeId, json.encode(termostatoVirtual))
  return termostatoVirtual
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
  -- en cualquier otro caso iniciarlo y devolverlo
  return resetDevice(nodeId)
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

--[[setActuador(actuator, start)
    (table)  actuator: tabla que representa un actuador
    (boolean) start: encender = true, apagar = false
  ordena el apagado/encendido a un actuador, este solo opera si la orden es
  contraria al estado actual de actuador --]]
function setActuador(actuator, start)
  -- si el actuador no está en modo mantenimiento
  toolKit:log(DEBUG, actuator.id)
  if actuator.id and actuator.id ~= 0 and not actuator.maintenance then
    -- comprobar estado actual
    local actuatorState = fibaro:getValue(actuator.id, actuator.statusPropertie)
    toolKit:log(DEBUG, 'Actuador : '..actuator.id..' con estado : '..
     actuatorState)
    -- si hay que encender y esta apagado
    if start and actuatorState == '0' then
      -- informar
      toolKit:log(INFO, 'Actuador-ON')
      fibaro:call(actuator.id, actuator.onFunction, 1)
    end
    -- si hay que apagar y está encendido
    if not start and actuatorState == '1' then
      -- informar
      toolKit:log(INFO, 'Actuador-OFF')
      fibaro:call(actuator.id, actuator.offFunction, 0)
    end
  end
end

--[[updateStatistics(PID, thingspeakKey)
  (table)   PID:  tabla que representa el PID
  (string)  thingspeakKey:  cadena con la Key del canal de thingspeakKey
  actualiza los valores en thingspeak --]]
function updateStatistics(PID, thingspeakKey)
  -- analizar resultado
  toolKit:log(DEBUG, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
   PID.integral..', D='..PID.derivativo..', S='..PID.result)
  --timestampPID = termostatoVirtual.PID['timestamp']
  if not thingspeak then
    thingspeak = Net.FHttp("api.thingspeak.com")
  end
  local payload = "key="..thingspeakKey.."&field1="..PID.newErr..
  "&field2="..PID.proporcional.."&field3="..PID.integral..
  "&field4="..PID.derivativo.."&field5="..PID.result..
  "&field6="..PID.targetLevel.."&field7="..PID.value
  local response, status, errorCode = thingspeak:POST('/update', payload)
end

-- actualizar etiqueta identificador
fibaro:call(_selfId, "setProperty", "ui.labelId.value",'id: '.._selfId)

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(_selfId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

  --[[Panel]]
  -- obtener el panel
  local panel = getPanel(fibaro:getRoomID(_selfId))
  -- si hay panel de calefacción para la habitación donde está el termostato
  if panel then
    toolKit:log(DEBUG, 'Nombre panel: '..panel.name)
    -- actualizar identificador del panel
    termostatoVirtual.panelId = panel.id
  else -- si no hay panel
    -- cambiar el modo a MANUAL y el identificador de panel a 0
    termostatoVirtual.panelId = 0
  end

  --[[temperarura actual]]
  -- si hay sonda declarada obtener la temperatura
  if termostatoVirtual.probeId and termostatoVirtual.probeId ~= 0 then
    termostatoVirtual.value  =
    tonumber(fibaro:getValue(termostatoVirtual.probeId, 'value'))
  elseif termostatoVirtual.probeId == 0 then
    -- si la sonda es virtual
    termostatoVirtual.value  = virtualProbe()
  end

  --[[temperarura de consigna]]
  -- comparar timestamp con os.time() y comprobar si hay panel
  if (termostatoVirtual.timestamp < os.time())
   and termostatoVirtual.panelId ~= 0
   and termostatoVirtual.mode ~= 0 then
    -- si es menor y status es AUTOMATICO, tomar temperatura del panel
    termostatoVirtual.targetLevel = getTargetLevel(panel)
    toolKit:log(DEBUG, 'Temperatura consigna: '..
    termostatoVirtual.targetLevel..'ºC')
  end

  --[[tiempo de protección]]
  -- si el modo no es OFF ni calibrando OFF=0 CALIBRANDO>=3
  if termostatoVirtual.mode > 0 and termostatoVirtual.mode < 3 then
    local shadowTime = termostatoVirtual.timestamp - os.time()
    -- si ha finalizado el tiempo de proteccion y hay panel
    if shadowTime <= 0 and termostatoVirtual.panelId ~= 0 then
      shadowTime = 0
      -- actualizar el modo de funcionamiento a AUTOMATICO
      termostatoVirtual.mode = 1
    else
      shadowTime = shadowTime / 60
      -- actualizar el modo de funcionamiento a MANUAL
      termostatoVirtual.mode = 2
    end
    -- actualizar etiqueda de modo de funcionamiento "mode""
    toolKit:log(DEBUG, 'Modo: '..mode[termostatoVirtual.mode])
    fibaro:call(_selfId, "setProperty", "ui.modeLabel.value",
     mode[termostatoVirtual.mode])
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
    fibaro:call(_selfId, "setProperty", "ui.timeLabel.value", timeLabel)
  else
    -- actualizar etiqueda de modo de funcionamiento "mode"
    fibaro:call(_selfId, "setProperty", "ui.modeLabel.value",
     mode[termostatoVirtual.mode])
  end

  -- guardar los cambios del dispositivo termostatoVirtual
  fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))

  -- si se ha cumplido el ciclo o si ha cambiado la consigna, calcular el PID
  if os.time() >= termostatoVirtual['PID'].checkPoint or
  termostatoVirtual.targetLevel ~= termostatoVirtual['PID'].targetLevel then
    -- asgnar la consgna y la temperatura actual
    termostatoVirtual['PID'].targetLevel = termostatoVirtual.targetLevel
    termostatoVirtual['PID'].value = termostatoVirtual.value
    -- actualizar dispositivo
    termostatoVirtual.PID = toolKit:calculatePID(termostatoVirtual.PID)
    -- actualizar estadísticas
    updateStatistics(termostatoVirtual.PID, thingspeakKey)
    -- guardar el nuevo PID
    fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
    -- recuperar dispositivo
    termostatoVirtual = getDevice(termostatoVirtual.nodeId)
  end

  --[[encendido / apagado
  si os.time() menor que el punto de cambio "changePoint" APAGADO
  si os.time() mayor o igual al punto de cambio, ENCENDIDO--]]
  if os.time() < termostatoVirtual['PID'].changePoint then
    -- informar
    toolKit:log(DEBUG, 'ON')
    -- anotar
    termostatoVirtual.oN = true
    -- actuar sobre el actuador si es preciso
    setActuador(termostatoVirtual.actuator, true)
  else
    -- informar
    toolKit:log(DEBUG, 'OFF')
    -- anotar
    termostatoVirtual.oN = false
    -- actuar sobre el actuador si es preciso
    setActuador(termostatoVirtual.actuator, false)
  end
  -- guardar nuevo estado oNoFf
  fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))

  -- actualizar icono y etiquetas
  local onOff = ' _'
  local icono = iconOFF
  if termostatoVirtual.oN then
    onOff = ' 🔥'
    icono = iconON
  end
  local targetLevel = string.format('%.2f', termostatoVirtual.targetLevel)
  local value = string.format('%.2f', termostatoVirtual.value )
  -- actualizar etiqueta
  fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value",
   value..'ºC / '..targetLevel..'ºC'..onOff)
  -- actualizar icono
  fibaro:call(_selfId, 'setProperty', "currentIcon", icono)

  -- esperar para evitar colapsar la CPU
  fibaro:sleep(1000)
  -- para control por watchdog
  toolKit:log(INFO, release['name']..' OK')
end

--[[--------- FIN BUCLE PRINCIPAL 🌛🔧🌡🔥🔘⏱📈 📟⚙-----------------------]]
