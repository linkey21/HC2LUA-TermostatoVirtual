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
   "tempId":0, "value":0 , "actuatorId":0, "zoneId":0, "panelId":0}']]
  local termostatoVirtual = {}
  -- almacenar el id del VD para saber que ha sido iniciada
  termostatoVirtual['nodeId'] = nodeId

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
  -- en cualquier otr caso iniciarlo y devolverlo
  return resetDevice(nodeId)
end

-- getPanelId(roomId)
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
  --[[
  monday, morning, hour, minute, temperature, day, evening, night,
  tuesday
  wednesday
  thursday
  friday
  saturday
  sunday
  handTemperature, handTimestamp, vacationTemperature
  --]]
  -- propiedades del panel
  local properties = panel.properties
  -- dia de la semana de hoy
  local dow = string.lower(tostring(os.date('%A')))
  toolKit:log(DEBUG, 'Dia de la semana: '..dow)
  -- tabla con propiedades del día de la semana
  local todayTab = properties[dow]
  toolKit:log(DEBUG, todayTab.morning.temperature)

  -- dia de la semana de ayer
  dow = string.lower(tostring(os.date('%A', os.time() - 24*60*60 )))
  toolKit:log(DEBUG, 'Dia de ayer: '..dow)
  -- tabla con propiedades de ayer
  local yesterdayTab = properties[dow]
  -- temperatura de la noche de ayer
  local temperatura = yesterdayTab['night'].temperature
  toolKit:log(DEBUG, 'Temperatura ayer noche: '..temperatura)

  local states = {'morning', 'day', 'evening', 'night'}
  local year, month, day = os.date('%Y'), os.date('%m'), os.date('%d')
  toolKit:log(DEBUG, os.time())
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
  return temperatura
end

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])
-- recuperar dispositivo
if not termostatoVirtual then termostatoVirtual = getDevice(_selfId) end
toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

--[[-- inicializar etiquetas --]]
fibaro:call(_selfId, "setProperty", "ui.separador.value", '======')
fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value", '20ºC / 21ºC')
fibaro:call(_selfId, "setProperty", "ui.timeLabel.value", '0m')
-- refrescar icono
fibaro:call(_selfId, 'setProperty', "currentIcon", iconoId)

-- obtener id del panel
local panel = getPanel(fibaro:getRoomID(_selfId))
if panel then
  toolKit:log(DEBUG, 'Nombre panel: '..panel.name)
end

-- comparar timestamp con os.time()
-- si es menor tomar temperatura del panel
local targetLevel = getTargetLevel(panel)
toolKit:log(DEBUG, 'Temperatura consigna: '..targetLevel..'ºC')
-- si en mayor tomar temperatura del VD

-- actualizar etiqueta de tiempo

fibaro:sleep(10000)
