--[[ TermostatoVirtual
	Dispositivo virtual
	downTempButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
local intervalo = 0.5
local maxTemp = 28
local shadowTime = 120 -- minutos en intervalos de 15min.
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
  -- recuperar temperaturas
  local value = termostatoVirtual.value
  local targetLevel = termostatoVirtual.targetLevel
  local onOff = ' _'
  -- disminuir intervalo
  if targetLevel >= intervalo then
    targetLevel = targetLevel - intervalo
  else
    targetLevel = maxTemp
  end

  --actualizar dispositivo
  termostatoVirtual.targetLevel = targetLevel
  -- proteger con un tiempo por defecto
  termostatoVirtual.timestamp = os.time() + shadowTime * 60
  -- guardar en variable global
  fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))

  -- actualizar la etiqueta
  targetLevel = string.format('%.2f', targetLevel)
  value = string.format('%.2f', value)
  local onOff = ' _'
  fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value",
   value..'ºC / '..targetLevel..'ºC'..onOff)
end

--[[--------------------------------------------------------------------------]]
