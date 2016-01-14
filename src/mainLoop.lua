--[[ TermostatoVirtual
	Dispositivo virtual
	mainLoop.lua
	por Manuel Pascual
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local iconoId = 1059
local kP = 200  -- Proporcional
local kI = 20   -- Integral
local kD = 20   -- Derivativo
local intervalo = 1 -- intervalo de medición en segundos
-- tiempo por ciclo en minutos: 10 minutos (6 ciclos/h) etc...
local tiempoCiclo = 5
local histeresis = 0.5 -- histeresis en grados
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='TermostatoVirtual.mainLoop', ver=1, mayor=0, minor=0}
local _selfId = fibaro:getSelfId()  -- ID de este dispositivo virtual
local mode = {}; mode[0]='OFF'; mode[1]='AUTO'; mode[2]='MANUAL'
local thingspeakKey = 'CQCLQRAU070GEOYY'
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
  local termostatoVirtual = {nodeId = nodeId, panelId = 0, probeId = 0,
  targetLevel = 0,   value = 0, mode = 1, timestamp = os.time()}
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
CalculoError(Actual, Consigna)
	Calculo del error diferencia entre temperatura Actual y Consigna
------------------------------------------------------------------------------]]
function CalculoError(currentTemp, Consigna)
	return tonumber(Consigna) - tonumber(currentTemp)
end

--[[
CalculoProporcional(Err,kP)
	Calculo del termino proporcional
------------------------------------------------------------------------------]]
function CalculoProporcional(Err,kP)
	P = Err*kP -- Termino proporcional
	return P
end

--[[
CalculoIntegral(acumErr, kI)
	Calculo del termino integral
------------------------------------------------------------------------------]]
function CalculoIntegral(acumErr, kI)
	I = acumErr*kI -- Termino integral
	return I
end

--[[
CalculoDerivativo(Err,lastErr,kD)
	Calculo del termino derivativo
------------------------------------------------------------------------------]]
function CalculoDerivativo(Err,lastErr,kD)
	D = (Err - lastErr)*kD -- Termino derivativo
	return D
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
  newErr = CalculoError(currentTemp, setPoint)
  -- calcular error acumulado  ajustado a histeresis
  toolKit:log(DEBUG, acumErr..' '..newErr..' '..histeresis)
  acumErr = AntiWindUp(acumErr, newErr, histeresis)
  -- calcular proporcional, integral y derivativo
  P = CalculoProporcional(newErr, kP)
  I = CalculoIntegral(acumErr, kI)
  D = CalculoDerivativo(newErr, lastErr, kD)
  -- guardar error como último error
  lastErr = newErr
  -- obtener el resultado
  result = P + I + D -- Accion total = P+I+D
  -- dajustar el resultado entro del ambito de tiempo de ciclo,
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

--[[setActuador(termostatoVirtual, actuatorId, actuador)
  --]]
function setActuador(actuatorId, actuador)
  -- si el actuador no está en modo mantenimiento
  if actuatorId and actuatorId ~= 0 then
    -- comprobar estado actual
    local actuatorState = fibaro:getValue(actuatorId, 'value')
    -- si hay que encender encender y esta apagado
    if actuador and actuatorState == 0 then
      -- encender
      fibaro:call(actuatorId, 'turnOn')
    end
    -- si hay que apagar y está encendido
    if not actuador and actuatorState == 1 then
      fibaro:call(actuatorId, 'turnOff')
    end
  end
end

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])

-- Inicializar Variables
local tiempoCiclo, factorEscala, Err, lastErr, acumErr, cicloStamp,
 offStamp = Inicializar()

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
while true do
  -- recuperar dispositivo
  local termostatoVirtual = getDevice(_selfId)
  toolKit:log(DEBUG, 'termostatoVirtual: '..json.encode(termostatoVirtual))
  -- icono
  fibaro:call(_selfId, 'setProperty', "currentIcon", iconoId)

  --[[Panel]]
  -- obtener el panel
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
    if termostatoVirtual.oN then onOff = ' 🔥' end
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
  -- comparar timestamp con os.time() y comprobar mode
  if (termostatoVirtual.timestamp < os.time()) and termostatoVirtual.mode ~= 0
   then
    -- si es menor y status no es OFF, tomar temperatura del panel
    local targetLevel = getTargetLevel(panel)
    local onOff = ' _'
    if termostatoVirtual.oN then onOff = ' 🔥' end
    toolKit:log(DEBUG, 'Temperatura consigna: '..targetLevel..'ºC')
    -- si la "targetLevel" es distionto de 0 actualizar al temperarura de consigna
    if targetLevel > 0 then
      local value = tonumber(termostatoVirtual.value)
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
  end

  --[[cálculo PID]]
  -- comprobar si se ha cumplido un ciclo para volver a calcular el PID
  if os.time() >= cicloStamp then
    -- leer temperatura de la sonda
    currentTemp = termostatoVirtual.value
    -- temperatura de consigna
    setPoint = termostatoVirtual.targetLevel
    -- ajustar el instante de apagado según el cálculo del tiempo de encendido
    -- y guardar el último error y error acumulado
    local onTime
    toolKit:log(INFO, 'Último error: '..lastErr..' Error acumulado: '..acumErr)
    onTime, lastErr, acumErr = calculatePID(currentTemp, setPoint, acumErr,
     lastErr, histeresis, factorEscala, tiempoCiclo)
    offStamp = tonumber(os.time() + onTime)
    -- ajustar en nuevo instante de cálculo PID
    cicloStamp = os.time() + tiempoCiclo
    toolKit:log(INFO, 'On '.. offStamp - os.time()..'s. - '..'Off '..
     cicloStamp - offStamp..'s.')
  end

  --[[encendido apagado]]
  -- si ha pasado el tiempo de encendido
  if os.time() >= offStamp then
    -- actualizar dispositivo si está encendido apagar
    if termostatoVirtual.oN then
      termostatoVirtual.oN = false
      fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
      toolKit:log(INFO, 'Apagar')
    end
    -- actuar sobre el actuador si es preciso
    setActuador(termostatoVirtual.actuatorId, false)
  else
    -- actualizar dispositivo si está apagado encender
    if not termostatoVirtual.oN then
      termostatoVirtual.oN = true
      fibaro:setGlobal('dev'.._selfId, json.encode(termostatoVirtual))
      toolKit:log(INFO, 'Encender')
    end
    -- actuar sobre el actuador si es preciso
    setActuador(termostatoVirtual.actuatorId, true)
  end

 fibaro:sleep(intervalo*1000)
end
--🌛 🔧  🔥  🔘
