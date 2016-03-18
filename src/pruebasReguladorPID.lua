--[[

--]]

--[[ TermostatoVirtual
	escena
	reguladorPID.lua
	por Manuel Pascual & Antonio Maestre
------------------------------------------------------------------------------]]

--[[----- CONFIGURACION DE USUARIO -------------------------------------------]]
local thermostatId = 631  -- id del termostato virtual
local configPanelId = 630  -- id del termostato virtual
-- thingspeakKey Key para registro y gráficas de temperatura
local thingspeakKey = 'BM0VMH4AF1JZN3QD'
--[[----- FIN CONFIGURACION DE USUARIO ---------------------------------------]]

--[[----- NO CAMBIAR EL CODIGO A PARTIR DE AQUI ------------------------------]]
-- si se inicia otra escena esta se suicida
if fibaro:countScenes() > 1 then
  fibaro:debug('terminado por nueva actividad')
  fibaro:abort()
end

--[[----- CONFIGURACION AVANZADA ---------------------------------------------]]
local release = {name='reguladorPID', ver=2, mayor=0, minor=0}
OFF=0;ERROR=1;INFO=2;DEBUG=3                -- referencia para el log
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
      if level == ERROR then color = 'red' end
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

--[[getObject(varName)
    (string) varName: nombre de la variable global que almacena los objetos
    si exite la variable global recuperar el último objeto
--]]
function getObject(varName)
  -- si  exite la variable global recuperar objetos
  local objects = isVariable(varName)
  if objects and objects ~= 'NaN' and objects ~= 0 and objects ~= '' then
    objects = json.decode(objects)
    -- devolver el último objeto
    table.sort(objects, function (a1, a2) return a1.id < a2.id end)
    return objects[#objects]
  end
  -- en cualquier otro caso error
  return false
end

--[[setObjet(varName, object)]]
function setObjet(varName, object)
  -- recuperar objetos
  local objects = isVariable(varName)
  if objects then
    objects = json.decode(objects)
    -- recorer la tabla para buscar el objetos y cambiar el valor
    for key, value in pairs(objects) do
      if value.id == object.id then
        objects[key] = value
        break
      end
    end
    -- guardar objetos
    fibaro:setGlobal(varName, json.encode(objects))
    return true
  end
  return false
end

function updateStatistics(PID)
  local postURL = "http://api.thingspeak.com/update"
  local postData = "key="..thingspeakKey.."&field1="..PID.newErr..
  "&field2="..PID.proporcional.."&field3="..PID.integral..
  "&field4="..PID.derivativo.."&field5="..PID.result..
  "&field6="..PID.targetLevel..
  "&field7="..PID.value

  local httpClient = net.HTTPClient({timeout=2000})
  httpClient:request(postURL, {
    success = function(response)
      if response.status == 200 then
        toolKit:log(INFO, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
        PID.integral..', D='..PID.derivativo..', S='..PID.result)
      else
        toolKit:log(ERROR, 'Error : ')
      end
    end,
    error = function(err)
      --toolKit:log(ERROR, 'Error : '..err)
    end,
    options = {
      method = "POST",
      --headers = {
      --  ["content-type"] = 'application/x-www-form-urlencoded;'
      --},
      data = postData,
      timeout = 5000
    }
  })
end

--[[cálculo PID]]
function calculatePID()
  -- inicializar el PID
  PID = getObject('PID')
  local K = PID.K

  -- calcular error
  PID.newErr = PID.targetLevel - PID.value

  -- calcular proporcional y si es negativo dejarlo a cero
  PID.proporcional = PID.newErr * K.kP
  if PID.proporcional < 0 then
    PID.proporcional = 0
    toolKit:log(INFO, 'proporcional < 0')
  end

  -- anti derivative kick usar el inverso de (currentTemp - lastInput) en
  -- lugar de error
  PID.derivativo = ((PID.value - PID.lastInput) * K.kD) * -1

  --[[reset del antiwindup
  si el error no esta comprendido dentro del ámbito de actuación del
  integrador, no se usa el cálculo integral y se acumula error = 0]]
  if math.abs(PID.newErr) > K.antiwindupReset then
  --if PID.newErr <= antiwindupReset then
    -- rectificar el resultado sin integrador
    PID.integral = 0
    PID.acumErr = 0
    toolKit:log(INFO, 'reset antiwindup del integrador ∓'..K.antiwindupReset)

  --[[uso normal del integrador
  se calcula el resultado con el error acumulado anterior y se acumula el
  error actual al error anterior]]
  else
    -- calcular integral
    PID.integral = PID.acumErr * K.kI
    PID.acumErr = PID.acumErr + PID.newErr
  end

  --[[antiwindup del integrador
  si el cálculo integral es mayor que el tiempo de ciclo, se ajusta el
  resultado al tiempo de ciclo y no se acumula el error]]
  if PID.integral > (3600 / K.cyclesH) then
    PID.integral = (3600 / K.cyclesH)
    toolKit:log(INFO, 'antiwindup del integrador > '..(3600 / K.cyclesH))
  end

  -- calcular salida
  PID.result = PID.proporcional + PID.integral + PID.derivativo

  --[[antiwindup de la salida
  si el resultado es mayor que el que el tiempo de ciclo, se ajusta el
  resultado al tiempo de ciclo meno tiempo mínimo y no se acumula el error]]
  if PID.result >= (3600 / K.cyclesH) then
    -- al menos apgar tiempo mínimo
    PID.result = (3600 / K.cyclesH) - K.minTimeAction
    toolKit:log(INFO, 'antiwindup salida > '..(3600 / K.cyclesH))
  elseif PID.result < 0 then
    PID.result = 0
    toolKit:log(INFO, 'antiwindup salida < 0')
  end

  --[[limitador por histeresis
  si error es menor o igual que la histeresis limitar la salida a 0, siempre
  que la tempeatura venga subiendo, no limitar hiteresis de bajada. Resetear
  el error acumulado. Si no hacemos esto tenemos acciones de control de la
  parte integral muy altas debidas a un error acumulado grande cuando estamos
  en histéresis. Eso provoca acciones integrales diferidas muy grandes]]
  if PID.result > 0 and math.abs(PID.newErr) <= K.histeresis then
    PID.acumErr = 0
    if PID.lastInput < PID.value then -- solo de subida
      PID.result = 0
      toolKit:log(INFO, 'histéresis error ∓'..K.histeresis)
    end
  end

  --[[límitador de acción mínima
  si el resultado es menor que el tiempo mínimo de acción, ajustar a 0.
  si se va a encender menos del tiempo mínimo, no encender]]
  if (PID.result <= math.abs(K.minTimeAction)) and (PID.result ~= 0) then
    PID.result = 0
    toolKit:log(INFO, 'tiempo salida ∓'..K.minTimeAction)
    --[[si se va a apgar menos de tiempo mínimo no apagar]]
  elseif PID.result > ((3600 / K.cyclesH) - K.minTimeAction) then
    PID.result = (3600 / K.cyclesH) - K.minTimeAction
  end

  -- informar
  toolKit:log(INFO, 'E='..PID.newErr..', P='..PID.proporcional..', I='..
  PID.integral..', D='..PID.derivativo..', S='..PID.result)

  -- recordar algunas variables para el proximo ciclo SE conservan en el PID
  --result, lastInput, acumErr = PID.result, termostatoVirtual.value,
  --PID.acumErr
  PID.lastInput = PID.value
  -- ajustar el punto de cambio de estado de la Caldera
  PID.changePoint = os.time() + PID.result
  -- añadir tiemstamp al PID
  PID.timestamp = os.time()

  -- actualizar dispositivo
  setObjet('PID', PID)

  -- informar
  toolKit:log(INFO, 'Error acumulado: '..PID.acumErr)
  toolKit:log(INFO, '-------------------------------------------------------')

  -- actualizar las estadísticas
  updateStatistics(PID)

  -- esperar al proximo ciclo o terminar
  if PID.alive then
    setTimeout(function() calculatePID(PID) end,
    3600000 / K.cyclesH)
  else
    toolKit:log(INFO, 'Fin')
  end
end -- function

--[[------- INICIA LA EJECUCION ----------------------------------------------]]
toolKit:log(INFO, release['name']..
' ver '..release['ver']..'.'..release['mayor']..'.'..release['minor'])
toolKit:log(INFO, '-------------------------------------------------------')

--[[--------- BUCLE PRINCIPAL ------------------------------------------------]]
local PID = getObject('PID')
toolKit:log(DEBUG, json.encode(PID))
if PID then
  setTimeout(function() calculatePID() end, 1)
else
  toolKit:log(ERROR, 'No hay variable para PID´s')
end
