--[[ TermostatoVirtual
	Dispositivo virtual
	mainLoop.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
iconoId = 1059
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='TermostatoVirtual.mainLoop', ver=1, mayor=0, minor=0}
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
OFF=1;INFO=2;DEBUG=3                -- referencia para el log
nivelLog = DEBUG                    -- nivel de log
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

--[[----------------------------------------------------------------------------
isVariable(varName)
	comprueba si existe una variable global dada(varName)
--]]
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
end

--[[----------------------------------------------------------------------------
resetDevice(nodeId)
	crea la varaible global para almacenar la tabla que representa el dispositivo
  inicializa en dispositivo.
--]]
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
  --[['{"nodeId":0, "deviceIcon":0, "targetLevel":0, "timestamp":0,
   "probeId":0, "value":0 , "actuatorId":0, "zoneId":0, "panelId":0}']]
  local termostatoVirtual = {}
  -- almacenar el id del VD para saber que ha sido iniciada
  termostatoVirtual['nodeId'] = nodeId
  termostatoVirtual['panelId'] = 0
  termostatoVirtual['probeId'] = 0
  termostatoVirtual['targetLevel'] = 0
  termostatoVirtual['value'] = 0
  termostatoVirtual['timestamp'] = os.time()

  -- guardar la tabla en la variable global
  fibaro:setGlobal('dev'..nodeId, json.encode(termostatoVirtual))

  -- devolver el dispositivo
  return termostatoVirtual
end

--[[----------------------------------------------------------------------------
getDevice(nodeId)
	recupera el dispositivo virtual desde la variable global
  (number)
--]]
function getDevice(nodeId)
  -- si  exite la variable global recuperar dispositivo
  local device = isVariable('dev'..nodeId)
  if device then
    device = json.decode(device)
    -- si esta iniciado devolver el dispositivo
    if device.nodeId then return device end
  end
  -- en cualquier otro caso iniciarlo y devolverlo
  return resetDevice(nodeId)
end

-- getPanel(roomId)
-- (number) roomId: id de la habitación
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

-- getTargetLevel(panel)
--(table) panel: tabla que representa un panel de temperatura
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

-- setProperty(property, value)
-- (string) property: nombre de la propiedad a actualizar
-- (various) value: valor a asignar a ala propiedad
function setProperty(property, value)
  return true
end

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])

-- inicializar etiquetas --
fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value",
 '00.00ºC / 00.00ºC _')
fibaro:call(_selfId, "setProperty", "ui.timeLabel.value", '00h 00m')
fibaro:call(_selfId, "setProperty", "ui.separador.value", '')
fibaro:call(_selfId, "setProperty", "ui.probeLabel.value", '🔧')
fibaro:call(_selfId, "setProperty", "ui.actuatorLabel.value", '🔧')
-- inicializar dispositivo
resetDevice(_selfId)


--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(_selfId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

  -- refrescar icono
  fibaro:call(_selfId, 'setProperty', "currentIcon", iconoId)

  --[[Panel]]
  -- obtener el  panel
  local panel = getPanel(fibaro:getRoomID(_selfId))
  if panel then
    toolKit:log(DEBUG, 'Nombre panel: '..panel.name)
    -- actualizar dispositivo
    termostatoVirtual.panelId = panel.id
    fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
  end

  --[[temperarura actual]]
  -- si hay sonda declarada obtener la temperatura
  if termostatoVirtual.probeId and termostatoVirtual.probeId ~= 0 then
    local value = tonumber(fibaro:getValue(termostatoVirtual.probeId, 'value'))
    local targetLevel = termostatoVirtual.targetLevel
    local onOff = ' _'
    if value < targetLevel then onOff = ' 🔥' end
    -- actualizar dispositivo
    termostatoVirtual.value = value
    fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
    -- actualizar etiqueta
    targetLevel = string.format('%.2f', targetLevel)
    value = string.format('%.2f', value)
    fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value",
     value..'ºC / '..targetLevel..'ºC'..onOff)
  end

  --[[temperarura de consigna]]
  -- comparar timestamp con os.time()
  if termostatoVirtual.timestamp < os.time() then
    -- si es menor tomar temperatura del panel
    local targetLevel = getTargetLevel(panel)
    local onOff = ' _'
    toolKit:log(INFO, 'Temperatura consigna: '..targetLevel..'ºC')
    -- si la "targetLevel" es distionto de 0 actualizar al temperarura de consigna
    if targetLevel > 0 then
      local value = tonumber(termostatoVirtual.value)
      if value < targetLevel then onOff = ' 🔥' end
      -- actualizar dispositivo
      termostatoVirtual.targetLevel = targetLevel
      fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
      -- actualizar etiqueta
      targetLevel = string.format('%.2f', targetLevel)
      value = string.format('%.2f', value)
      fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value",
       value..'ºC / '..targetLevel..'ºC'..onOff)
    end
  end

  --[[tiempo de protección]]
  local shadowTime = termostatoVirtual.timestamp - os.time()
  if shadowTime <= 0 then shadowTime = 0 else shadowTime = shadowTime / 60 end
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

  fibaro:sleep(10000)
end
--🌛 🔧  🔥
