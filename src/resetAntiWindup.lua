function calculatePID()
  calculoProporcional(newErr , kP) +
  calculoIntegral(acumErr, kI) +
  calculoDerivativo(currentTemp - lastInput, kD)
end

termostatoVirtual.value,
 termostatoVirtual.targetLevel, acumErr, lastInput, cycleTime, histeresis

-- calcular error
newErr = calculoError(termostatoVirtual.value, termostatoVirtual.targetLevel)
local result
--[[reset del antiwindup
si el error no esta comprendido dentro del ambito de actuación del integrador,
no se usa el cálculo integral, error acumulado = 0]]
if newErr > antiwindupReset and newErr < (0 - antiwindupReset) then
  acumErr = 0
  -- obtener el resultado sin integrador
  result = calculatePID(newErr, acumErr, termostatoVirtual.value, lastInput,
   kP, kI, kP)
elseif PID.integral > tiempo then
  --[[antiwindup del integrador
  si el cálculo integral es mayor que el tiempo de ciclo, se ajusta el resultado
  al tiempo de ciclo y se limita el integrador al no acumular el error]]
  acumErr = acumErr
  result = tiempo
else -- acumulado normal
  --[[uso normal del integrador
  primero se calcula el resultado con el error actual y se acumula el error al
  error anterior ]]
  -- obtener el resultado
  result = calculatePID(newErr, acumErr, termostatoVirtual.value, lastInput,
   kP, kI, kP)
   -- acumular error
  acumErr = acumErr + newErr
end
--[[antiwindup de la salida
si el resultado es mayor que el que el tiempo de ciclo,se ajusta el resultado
al tiempo de ciclo y se limita el integrador al no acumular el error]]
if result > tiempo then
  result = ciclo
  acumErr = acumErr
end


-- recordar algunas variables para el proximo ciclo
result, lastInput, acumErr = PID.result, termostatoVirtual.value,
PID.acumErr
