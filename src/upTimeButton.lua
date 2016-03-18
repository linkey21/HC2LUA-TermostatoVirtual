--[[ TermostatoVirtual
	Dispositivo virtual
	upTimeButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]

-- isVariable(varName)
-- (string) varName: nombre de la variable global
-- comprueba si existe una variable global dada
function isVariable(varName)
  -- comprobar si existe
  local valor, timestamp = fibaro:getGlobal(varName)
  if (valor and timestamp > 0) then return valor end
  return false
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
    return json.decode(device)
  end
end

-- recuperar dispositivo
local termostatoVirtual = getDevice(_selfId)

-- comprobar que no está en modo MANUAL
if termostatoVirtual.mode ~= 0 then
  local textMin = {}
  textMin['00h 00m']   = 0; textMin['00h 15m']  = 15; textMin['00h 30m']  = 30
  textMin['00h 45m']  = 45; textMin['01h 00m']  = 60; textMin['01h 15m']  = 75
  textMin['01h 30m']  = 90; textMin['01h 45m'] = 105; textMin['02h 00m'] = 120
  textMin['02h 15m'] = 135; textMin['02h 30m'] = 150; textMin['02h 45m'] = 165
  textMin['03h 00m'] = 180; textMin['03h 15m'] = 195; textMin['03h 30m'] = 210
  textMin['03h 45m'] = 225; textMin['04h 00m'] = 240; textMin['04h 15m'] = 255
  textMin['04h 30m'] = 270; textMin['04h 45m'] = 285; textMin['05h 00m'] = 300
  textMin['05h 15m'] = 315; textMin['05h 30m'] = 330; textMin['05h 45m'] = 345
  textMin['06h 00m'] = 360
  local minText = {}
  minText[0]   = '00h 00m'; minText[15]  = '00h 15m'; minText[30]  = '00h 30m'
  minText[45]  = '00h 45m'; minText[60]  = '01h 00m'; minText[75]  = '01h 15m'
  minText[90]  = '01h 30m'; minText[105] = '01h 45m'; minText[120] = '02h 00m'
  minText[135] = '02h 15m'; minText[150] = '02h 30m'; minText[165] = '02h 45m'
  minText[180] = '03h 00m'; minText[195] = '03h 15m'; minText[210] = '03h 30m'
  minText[225] = '03h 45m'; minText[240] = '04h 00m'; minText[255] = '04h 15m'
  minText[270] = '04h 30m'; minText[285] = '04h 45m'; minText[300] = '05h 00m'
  minText[315] = '05h 15m'; minText[330] = '05h 30m'; minText[345] = '05h 45m'
  minText[360] = '06h 00m'

  -- recuperar etiqueta de tiempo
  local time = textMin[fibaro:get(_selfId, 'ui.timeLabel.value')]
  -- aumentar 15min
  if time < 360 then time = time + 15 else time = 0 end

  -- actualizar la etiqueta
  fibaro:call(_selfId, "setProperty", "ui.timeLabel.value", minText[time])
  -- recuperar dispositivo
  termostatoVirtual = getDevice(_selfId)
  --actualizar dispositivo
  termostatoVirtual.timestamp = os.time() + time * 60
  fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
end
--[[--------------------------------------------------------------------------]]
