--[[ TermostatoVirtual
	escena
	reguladorPID.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local thermostatId = 587  -- id del termostato virtual
local tiempoCiclo = 600   -- tiempo por ciclo de calefacción en segundos
local histeresis = 0.2    -- histeresis en grados
local kP = 150            -- Proporcional
local kI = 20             -- Integral
local kD = 40             -- Derivativo
local thingspeakKey = 'CQCLQRAU070GEOYY'
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='reguladorPID', ver=1, mayor=0, minor=0}
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
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
      toolKit:log(DEBUG, 'nodeId: '..device.nodeId)
      return device
     end
  end
  -- en cualquier otro caso error
  return false
end

--[[Inicializar()
  Inicializa variables --]]
function Inicializar()
	--if tiempoCiclo < 5 then tiempoCiclo = 5 end -- ciclo mínimo es de 5 min
	local Err = 0 -- Error: diferencia entre consigna y valor actual
	local lastErr = 0 -- Error en la iteracion anterior
	local acumErr = 0 -- Suma error calculado
  local cicloStamp = os.time() -- timestamp hasta próximo ciclo
  local changePoint = os.time() -- punto de cambio de estado de la Caldera
  local inicioCiclo = os.time() -- se inicia el ciclo
  local result = 0 -- resultado salida del PID
	return tiempoCiclo, Err, lastErr, acumErr,
   cicloStamp, changePoint, inicioCiclo, result
end

--[[calculoError(Actual, Consigna)
	Calculo del error diferencia entre temperatura Actual y Consigna
------------------------------------------------------------------------------]]
function calculoError(currentTemp, Consigna)
	return tonumber(Consigna) - tonumber(currentTemp)
end

--[[calculoProporcional(Err,kP)
	Calculo del termino proporcional
------------------------------------------------------------------------------]]
function calculoProporcional(err, kP)
	P = err * kP -- Termino proporcional
	return P
end

--[[calculoDerivativo(Err,lastErr,kD)
	Calculo del termino derivativo
------------------------------------------------------------------------------]]
function calculoDerivativo(err,lastErr,kD)
	D = (err - lastErr) * kD -- Termino derivativo
	return D
end

--[[calculoIntegral(acumErr, kI)
	Calculo del termino integral
------------------------------------------------------------------------------]]
function calculoIntegral(acumErr, kI)
	I = acumErr * kI -- Termino integral
	return I
end

--[[antiWindUpH(result, tiempo, acumErr, newErr, histeresis, P, D, kI) --]]
function antiWindUpH(result, tiempo, acumErr, newErr, histeresis, P, D, kI)
  -- si el resultado está dentro del anbito de tiempo de ciclo, no hay windUp
  if ((result < tiempo) and (result > (0 - tiempo))) then
    -- si el resultado esta dentro del ambito de histeresis, ajustar histeresis
    if newErr <= histeresis and newErr > 0 then
      -- devolver el error acumulado en el integrador para que el resultado sea
      -- igual a 0 y devolver 0 como resultado
      toolKit:log(INFO, 'Ajuste histéresis')
      return (0 - (P +D)) / kI, 0
    end
    -- devolver el error acumulado en el integrador y el resultado
    return acumErr + newErr, result
  end
  -- si el resultado está fuera del ambito de ciclo de tiempo devolver el error
  -- para el integrador para que el resultado sea igual al ciclo de tiempo y el
  -- rciclo de tiempo como resultado
  toolKit:log(INFO, 'Ajuste antiWindUp')
  return (tiempo - (P + D)) / kI, tiempo
end

--[[calculatePID(currentTemp, setPoint)
(number) currentTemp: temperatura actual de la sonda
(number) setPoint: temperatura de consigna
Calcula utilizando un PID el tiempo de encendido del sistema]]
function calculatePID(currentTemp, setPoint, acumErr, lastErr, tiempo,
  histeresis)
  local newErr, result = 0, 0
  -- calcular error
  newErr = calculoError(currentTemp, setPoint)
  -- calcular proporcional, Integra y derivativo
  P = calculoProporcional(newErr, kP)
  D = calculoDerivativo(newErr, lastErr, kD)
  I = calculoIntegral(acumErr, kI)
  -- obtener el resultado
  result = P + I + D -- Accion total = P+I+D
  -- si el resultado entra en histéresis, calcular el integrador para que el
  -- resultado sea 0
  -- si el resultado sale del rango de ciclo de tiempo calcula el integrador
  -- para que el resultado sea el límete de tiempo.
  acumErr, result = antiWindUpH(result, tiempo, acumErr, newErr, histeresis,
   P, D, kI)
  -- calcular error acumulado antiWindUp integral
  --acumErr = antiWindUpInt(result, tiempo, acumErr, newErr, histeresis)
  -- ajustar la salida definitiva antiWindUp Salida
  --result = antiWindUpRes(result, tiempo, newErr, histeresis)
  -- informar del resultado
  toolKit:log(INFO, 'E='..newErr..', P='..P..', I='..I..', D='..D..
   ', S='..result)
  -- analizar resultado
  if not thingspeak then
    thingspeak = Net.FHttp("api.thingspeak.com")
  end
  local payload = "key="..thingspeakKey.."&field1="..newErr.."&field2="..P
   .."&field3="..I.."&field4="..D.."&field5="..result
  local response, status, errorCode = thingspeak:POST('/update', payload)
  -- devolver el resultado, nuevo error y error acumulado
  toolKit:log(DEBUG, 'Cálculo PID: '..result..' '..newErr..' '..acumErr)
  return result, newErr, acumErr
end

--[[setActuador(termostatoVirtual, actuatorId, actuador)
  --]]
function setActuador(actuatorId, actuador)
  -- si el actuador no está en modo mantenimiento
  if actuatorId and actuatorId ~= 0 then
    -- comprobar estado actual
    local actuatorState = fibaro:getValue(actuatorId, 'value')
    -- si hay que encender y esta apagado
    if actuador and actuatorState == '0' then
      -- encender
      fibaro:call(actuatorId, 'turnOn')
    end
    -- si hay que apagar y está encendido
    if not actuador and actuatorState == '1' then
      fibaro:call(actuatorId, 'turnOff')
    end
  end
end

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])

-- Inicializar Variables
local tiempoCiclo, Err, lastErr, acumErr, cicloStamp, changePoint, inicioCiclo,
 result = Inicializar()

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- esperar hsata que exista el termostato
  while not getDevice(thermostatId) do
    toolKit:log(DEBUG, 'Espeando por el termostato')
  end
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(thermostatId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

  --[[Panel]]
  -- obtener el panel
  local panel = getPanel(fibaro:getRoomID(thermostatId))
  if panel then
    toolKit:log(DEBUG, 'Nombre panel: '..panel.name)
    -- actualizar dispositivo
    termostatoVirtual.panelId = panel.id
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
  end

  --[[temperarura actual]]
  -- si hay sonda declarada obtener la temperatura
  if termostatoVirtual.probeId and termostatoVirtual.probeId ~= 0 then
    local value = tonumber(fibaro:getValue(termostatoVirtual.probeId, 'value'))
    -- offSet de la sonda
    value = value + offSetSonda
    local targetLevel = termostatoVirtual.targetLevel
    local onOff = ' _'
    if termostatoVirtual.oN then onOff = ' 🔥' end
    -- actualizar dispositivo
    termostatoVirtual.value = value
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    -- actualizar etiqueta
    targetLevel = string.format('%.2f', targetLevel)
    value = string.format('%.2f', value)
    fibaro:call(thermostatId, "setProperty", "ui.actualConsigna.value",
     value..'ºC / '..targetLevel..'ºC'..onOff)
  end

  --[[temperarura de consigna]]
  -- comparar timestamp con os.time() y comprobar mode
  if (termostatoVirtual.timestamp < os.time()) and termostatoVirtual.mode ~= 0
   then
    -- si es menor y status no es OFF, tomar temperatura del panel
    local targetLevel = getTargetLevel(panel)
    local onOff = ' _'
    if termostatoVirtual.oN then onOff = ' 🔥' end
    toolKit:log(DEBUG, 'Temperatura consigna: '..targetLevel..'ºC')
    -- si la "targetLevel" es distinto de 0 actualizar temperarura de consigna
    if targetLevel > 0 then
      local value = tonumber(termostatoVirtual.value)
      -- actualizar dispositivo
      termostatoVirtual.targetLevel = targetLevel
      fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
      -- actualizar etiqueta
      targetLevel = string.format('%.2f', targetLevel)
      value = string.format('%.2f', value)
      fibaro:call(thermostatId, "setProperty", "ui.actualConsigna.value",
       value..'ºC / '..targetLevel..'ºC'..onOff)
    end
  end

  --[[tiempo de protección]]
  -- si el modo es no es OFF
  if termostatoVirtual.mode ~= 0 then
    local shadowTime = termostatoVirtual.timestamp - os.time()
    if shadowTime <= 0 then
      shadowTime = 0
      -- actualizar estado del dispositivo
      termostatoVirtual.mode = 1
    else
      shadowTime = shadowTime / 60
      -- actualizar estado del dispositivo
      termostatoVirtual.mode = 2
    end
    -- actualizar dispositivo
    fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
    -- actualizar etiqueda de modo de funcionamiento "mode""
    toolKit:log(DEBUG, 'Modo: '..mode[termostatoVirtual.mode])
    fibaro:call(thermostatId, "setProperty", "ui.modeLabel.value",
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
    fibaro:call(thermostatId, "setProperty", "ui.timeLabel.value", timeLabel)
  end

  --[[comprobar inicio de ciclo--]]
  if (os.time() - inicioCiclo) >= tiempoCiclo then inicioCiclo = os.time() end
  -- if os.time() >= changePoint then inicioCiclo = os.time() end

  --[[cálculo PID]]
  -- comprobar si se ha cumplido un ciclo para volver a calcular el PID
  if os.time() >= cicloStamp then
    -- leer temperatura de la sonda
    currentTemp = termostatoVirtual.value
    -- temperatura de consigna
    setPoint = termostatoVirtual.targetLevel
    -- ajustar el instante de apagado según el cálculo PID y guardar el último
    -- error y error acumulado
    result, lastErr, acumErr = calculatePID(currentTemp, setPoint, acumErr,
     lastErr, tiempoCiclo, histeresis)
    -- ajustar el punto de cambio de estado de la Caldera
    changePoint = inicioCiclo + result
    -- ajustar el nuevo instante de cálculo PID
    cicloStamp = os.time() + intervalo
    -- informar
    toolKit:log(INFO, 'Error acumulado: '..acumErr)
  end

  --[[encendido / apagado]]
  -- si la salida es mayor que el tiempo desde que se encendió, apagar
  if os.time() < changePoint then
    -- actualizar solo si el dispositivo cambia de estado
    if not termostatoVirtual.oN then
      --if not inHisteresis(lastErr, histeresis) then
        -- actualizar dispositivo
        termostatoVirtual.oN = true
        fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
        -- informar
        toolKit:log(INFO, 'ON '..(changePoint - os.time()))
        -- actuar sobre el actuador si es preciso
        setActuador(termostatoVirtual.actuatorId, true)
      --else
      --  toolKit:log(INFO, 'histeresis')
      --end
    end
  else
    -- actualizar solo si el dispositivo cambia de estado
    if termostatoVirtual.oN then
      -- actualizar dispositivo
      termostatoVirtual.oN = false
      fibaro:setGlobal('dev'..thermostatId, json.encode(termostatoVirtual))
      -- informar
      toolKit:log(INFO, 'OFF '..(tiempoCiclo - (os.time() - inicioCiclo)))
      -- actuar sobre el actuador si es preciso
      setActuador(termostatoVirtual.actuatorId, false)
    end
  end

 fibaro:sleep(1000)
end
--🌛 🔧  🔥  🔘
