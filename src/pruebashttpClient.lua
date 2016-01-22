local httpClient = net.HTTPClient();
httpClient:request('http://api.thingspeak.com/update', {
  success = function(response)
    if tonumber(response.status) == 200 then
      print("Updated at " .. os.date());
    else
      print("Error " .. response.status)
    end
  end,
  error = function(err)
    print('error = ' .. err)
  end,
  options = {
    method = 'PUT',
    headers = {
      ["content-type"] = 'application/x-www-form-urlencoded;'
    },
    data = "key=BM0VMH4AF1JZN3QD&field1=100&field2=100&field3=100&field4=100&field5=100"
  }
});
