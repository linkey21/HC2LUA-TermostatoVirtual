--[[
%% autostart
--]]

--[[ TermostatoVirtual
	escena
	HRT-PID.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
-- thingspeakKey Key para registro y gráficas de temperatura
local thingspeakKey = 'BM0VMH4AF1JZN3QD'
local actuatorId = 595
local probeId = 592
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

while true do
  local estado = fibaro:getValue(actuatorId, 'mode') -- '0' apagado
  local stamp = os.time()
  -- esperar mientras no cambie el estado
  fibaro:debug('esperando...'..estado)
  while estado == fibaro:getValue(actuatorId, 'mode') do fibaro:sleep(1000) end
  -- si el estado es apagado es que ha estado encendido
  fibaro:debug('calculando...'..estado)
  if fibaro:getValue(actuatorId, 'mode') == '0' then
    -- calcular tiempo que ha estado encendido corresponde a la salida del PID
    local salida = os.time() - stamp
    -- obtener temperatura actual
    local temp = fibaro:getValue(probeId, "value")
    -- enviar datos a thingspeak
    if not thingspeak then
      thingspeak = Net.FHttp("api.thingspeak.com")
    end
    fibaro:debug('Salida: '..salida..' Temperatura: '..temp)
    local payload = "key="..thingspeakKey.."&field1="..salida.."&field2="..temp
    local response, status, errorCode = thingspeak:POST('/update', payload)
  end
end
