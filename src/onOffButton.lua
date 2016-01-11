--[[ TermostatoVirtual
	Dispositivo virtual
	onOffButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
local offTemperature = 5 -- ºC
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

-- --actualizar dispositivo
if termostatoVirtual.mode == 0 then
	termostatoVirtual.mode = 1
else
	termostatoVirtual.mode = 0
	termostatoVirtual.targetLevel = offTemperature
end
-- guardar en variable global
fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
-- actualizar etiqueda de modo de funcionamiento "mode""
fibaro:call(_selfId, "setProperty", "ui.modeLabel.value",
 mode[termostatoVirtual.mode])

fibaro:debug(mode[termostatoVirtual.mode])
