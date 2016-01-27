--[[ TermostatoVirtual
	Dispositivo virtual
	statusButton.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
-- thingspeakKey Key para registro y gráficas de temperatura
local thingspeakKey = 'CQCLQRAU070GEOYY'
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
--[[----- FIN CONFIGURACION AVANZADA -----------------------------------------]]

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

-- recuperar dispositivo
local termostatoVirtual = getDevice(fibaro:getSelfId())

-- actualizar cuando se anota salida del PID.
--if termostatoVirtual.PID and termostatoVirtual.PID['timestamp'] ~= timestampPID then
  local PID = termostatoVirtual.PID
  -- analizar resultado
  fibaro:debug('E='..PID.newErr..', P='..PID.proporcional..', I='..
   PID.integral..', D='..PID.derivativo..', S='..PID.result)
  --timestampPID = termostatoVirtual.PID['timestamp']
  if not thingspeak then
    thingspeak = Net.FHttp("api.thingspeak.com")
  end
  local payload = "key="..thingspeakKey.."&field1="..PID.newErr..
  "&field2="..PID.proporcional.."&field3="..PID.integral..
  "&field4="..PID.derivativo.."&field5="..PID.result..
  "&field6="..termostatoVirtual.targetLevel.."&field7="..termostatoVirtual.value
  local response, status, errorCode = thingspeak:POST('/update', payload)
--end
