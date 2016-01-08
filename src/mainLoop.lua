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
    if mensaje == nil then mensaje = 'nil' end
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

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])
-- recuperar dispositivo
if not termostatoVirtual then termostatoVirtual = getDevice(_selfId) end
toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

fibaro:call(_selfId, "setProperty", "ui.separador.value", '======')
fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value", '20ºC / 21ºC')
-- refrescar icono
fibaro:call(_selfId, 'setProperty', "currentIcon", iconoId)

--[[-- ccomprobar si existe la variable global y crearla --]]

--[[ comparar timestamp con os.time()
  si es menor
    tomar temperatura del panel

  si en mayor
    tomar temperatura del VD

  actualizar etiqueta de tiempo
--]]
fibaro:sleep(10000)
