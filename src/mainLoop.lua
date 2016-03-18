--[[ TermostatoVirtual
	Dispositivo virtual
	mainLoop.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
-- id de los iconos ON OFF
local iconON = 1067
local iconOFF = 1066
--[[ nombre de la funcion que hay que usar para encender/apagar el actuador y
     delnombre de la propieda que muestra el estado
local actuatorOn = 'turnOn'
local actuatorOff = 'turnOff'
local actuatorStatus = 'value'
--]]
local actuatorOn = 'setMode'
local actuatorOff = 'setMode'
local actuatorStatus = 'mode'
-- función para obtener la temperatura de la sonda virtual, escribir a
-- continuación de 'return' el código o expresión para obtener la temperatura
local virtualProbe = function (self, ...)
  local t = fibaro:getValue(389, 'value')
  return math.floor((t - ((41 - t) / t)) * 100) / 100
end
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='termostatoVirtual', ver=1, mayor=0, minor=2}
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
mode[3]='CALIBRADO_F1'; mode[4]='CALIBRADO_F2'; mode[5]='CALIBRADO_FIN'
if not oN then oN = true end
if not timestampPID then timestampPID = os.time() end
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

--[[resetDevice(nodeId)
    (number) nodeId: número del dispositivo a almacenar en la variable global
crea una varaible global para almacenar la tabla que representa el
dispositivo y lo inicializa. --]]
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
  local K = {kP = 0, antiwindupReset = 0, kD = 0, tuneTime = 0,
   minTimeAction = 0, cyclesH = 0, kI = 0, histeresis = 0}
  local PID = {result = 0, newErr = 0, acumErr = 0, proporcional = 0,
   integral = 0, derivativo = 0, lastInput = 0}
  local termostatoVirtual = {PID = PID, K = K, nodeId = nodeId, panelId = 0,
   probeId = 0, targetLevel = 0, value = 0, mode = 1, timestamp = os.time(),
   oN=false}
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

<<<<<<< HEAD
--[[Inicializar()
  Inicializa variables --]]
function Inicializar()
	--if tiempoCiclo < 5 then tiempoCiclo = 5 end -- ciclo mínimo es de 5 min
	local factorEscala = 1
	local Err = 0 -- Error: diferencia entre consigna y valor actual
	local lastErr = 0 -- Error en la iteracion anterior
	local acumErr = 0 -- Suma error calculado
  local cicloStamp = os.time() -- timestamp hasta próximo ciclo
  -- timestamp hasta próximo apagado
  local offStamp = os.time() + tiempoCiclo * 60
	return (tiempoCiclo * 60) * factorEscala, factorEscala, Err, lastErr, acumErr,
   cicloStamp, offStamp
end
--[[
calculoError(Actual, Consigna)
	Calculo del error diferencia entre temperatura Actual y Consigna
------------------------------------------------------------------------------]]
function calculoError(currentTemp, Consigna)
	return tonumber(Consigna) - tonumber(currentTemp)
end

--[[
calculoProporcional(Err,kP)
	Calculo del termino proporcional
------------------------------------------------------------------------------]]
function calculoProporcional(err, kP)
	P = err * kP -- Termino proporcional
	return P
end

--[[
calculoDerivativo(Err,lastErr,kD)
	Calculo del termino derivativo
------------------------------------------------------------------------------]]
function calculoDerivativo(err, lastErr, kD)
	D = (err - lastErr) * kD -- Termino derivativo
	return D
end

--[[
calculoIntegral(acumErr, kI)
	Calculo del termino integral
------------------------------------------------------------------------------]]
function calculoIntegral(acumErr, kI)
	I = acumErr * kI -- Termino integral
	return I
end

--[[
AntiWindUp(acumErr, Err, Histeresis)
------------------------------------------------------------------------------]]
function AntiWindUp(acumErr, Err, histeresis)
	-- si el error está fuera del rango de histeresis, acumular error
	if math.abs(Err) > histeresis then
		return acumErr + Err
	end
	-- si está dentro del rango de histeresis, anti WindUp
	return 0
end

--[[calculatePID(currentTemp, setPoint)
(number) currentTemp: temperatura actual de la sonda
(number) setPoint: temperatura de consigna
Calcula utilizando un PID el tiempo de encendido del sistema]]
function calculatePID(currentTemp, setPoint, acumErr, lastErr, histeresis,
   factor, tiempo)
  local newErr, result
  -- calcular error
  newErr = calculoError(currentTemp, setPoint)
  -- calcular error acumulado ajustado a histeresis
  toolKit:log(DEBUG, acumErr..' '..newErr..' '..histeresis)
  acumErr = AntiWindUp(acumErr, newErr, histeresis)
  -- calcular proporcional, integral y derivativo
  P = calculoProporcional(newErr, kP)
  I = calculoDerivativo(newErr, lastErr, kD)
  D = calculoIntegral(acumErr, kI)
  -- guardar error como último error
  lastErr = newErr
  -- obtener el resultado
  result = P + I + D -- Accion total = P+I+D
  -- dajustar el resultado dentro del ambito de tiempo de ciclo,
  -- aplicando si procede factor de escala.
  result = adjustResult(result, factor, tiempo)
  -- informar del resultado
  toolKit:log(INFO, 'E='..newErr..', P='..P..', I='..I..', D='..D..
   ' ,S='..result)
  -- analizar resultado
  if not thingspeak then
    thingspeak = Net.FHttp("api.thingspeak.com")
  end
  local payload = "key="..thingspeakKey.."&field1="..newErr.."&field2="..P
   .."&field3="..I.."&field4="..D.."&field5="..result
  local response, status, errorCode = thingspeak:POST('/update', payload)
  -- devolver el resultado y los nuevos error y error acumulado
  toolKit:log(DEBUG, 'Cálculo PID: '..result..' '..lastErr..' '..acumErr)
  return result, lastErr, acumErr
end

--[[adjustResult(value, factorEscala, tiempoCiclo)
  (number) value: valor salida del calculo PID
  (number) factor: factor de escala para ajustar en pruebas
  (number) tiempo: tiempo de ciclo
  ajusta el  resultado dentro del ambito del tiempo de ciclo y limitado por
  histéresis--]]
function adjustResult(value, factor, tiempo)
  -- ajusar el valor dentro del tiempo de ciclo
  if value > tiempo then value = tiempo end
  if value < (0 - tiempo) then value = (0 - tiempo) end
  -- devolver el valor ajustado por factor de escala
  return value * factor
end

=======
>>>>>>> OnOff
--[[setActuador(termostatoVirtual, actuatorId, actuador)
  --]]
function setActuador(actuatorId, actuador)
  -- si el actuador no está en modo mantenimiento
  toolKit:log(DEBUG, actuatorId)
  if actuatorId and actuatorId ~= 0 then
    toolKit:log(DEBUG, 'Hay actuador')
    -- comprobar estado actual
    local actuatorState
    local actuatorState = fibaro:getValue(actuatorId, actuatorStatus)
    -- si hay que encender y esta apagado
    toolKit:log(DEBUG, actuatorState)
    if actuador and actuatorState == '0' then
      -- informar
      toolKit:log(INFO, 'Actuador-ON')
      --fibaro:call(617, 'turnOn')
      fibaro:call(actuatorId, actuatorOn, 1)
    end
    -- si hay que apagar y está encendido
    if not actuador and actuatorState == '1' then
      -- informar
      toolKit:log(INFO, 'Actuador-OFF')
      --fibaro:call(617, 'turnOff')
      fibaro:call(actuatorId, actuatorOff, 0)
    end
  end
end

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(_selfId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))

  -- actualizar etiqueta identificador
  fibaro:call(_selfId, "setProperty", "ui.labelId.value",'id: '.._selfId)

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
  -- actualizar dispositivo
  fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))

  --[[temperarura actual]]
  -- si hay sonda declarada obtener la temperatura
  local value, targetLevel = 0, 0
  if termostatoVirtual.probeId and termostatoVirtual.probeId ~= 0 then
    value = tonumber(fibaro:getValue(termostatoVirtual.probeId, 'value'))
  elseif termostatoVirtual.probeId == 0 then
    -- si la sonda es virtual
    value = virtualProbe()
  end

  --[[temperarura de consigna]]
  -- comparar timestamp con os.time() y comprobar si hay panel
  if (termostatoVirtual.timestamp < os.time()) and termostatoVirtual.panelId ~= 0
   and termostatoVirtual.mode ~= 0
   then
    -- si es menor y status es AUTOMATICO, tomar temperatura del panel
    targetLevel = getTargetLevel(panel)
    toolKit:log(DEBUG, 'Temperatura consigna: '..targetLevel..'ºC')
  end

  -- actualizar dispositivo (temperarura y consigna)
  termostatoVirtual.value = value
  -- si la "targetLevel" es distinto de 0 actualizar temperarura de consigna
  if targetLevel > 0 then
    termostatoVirtual.targetLevel = targetLevel
  end
  fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))

  -- actualizar icono y etiquetas
  local onOff = ' _'
  local icono = iconOFF
  local targetLevel = tonumber(getDevice(_selfId).targetLevel)
  local value = tonumber(getDevice(_selfId).value)
  if termostatoVirtual.oN then
    onOff = ' 🔥'
    icono = iconON
  end
  targetLevel = string.format('%.2f', targetLevel)
  value = string.format('%.2f', value)
  -- actualizar etiqueta
  fibaro:call(_selfId, "setProperty", "ui.actualConsigna.value",
   value..'ºC / '..targetLevel..'ºC'..onOff)
  -- actualizar icono
  fibaro:call(_selfId, 'setProperty', "currentIcon", icono)

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
    -- actualizar dispositivo
    fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
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

  --[[encendido / apagado]]
  -- actualizar solo si el dispositivo cambia de estado
  --if termostatoVirtual.oN ~= on then
  if termostatoVirtual.oN then
    -- informar
    toolKit:log(DEBUG, 'ON')
    -- actuar sobre el actuador si es preciso
    setActuador(termostatoVirtual.actuatorId, true)
  else
    -- informar
    toolKit:log(DEBUG, 'OFF')
    -- actuar sobre el actuador si es preciso
    setActuador(termostatoVirtual.actuatorId, false)
  end

  -- esperar para evitar colapsar la CPU
  fibaro:sleep(1000)
  -- para control por watchdog
  toolKit:log(INFO, release['name']..' OK')

end

--🌛🔧🌡🔥🔘⏱📈
