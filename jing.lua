local URL = "https://vercel-lua-protector-preview.vercel.app/api/script"
local ACCESS_TOKEN = "R1aYKGI2EYHrRPwZIpqgOxyuMMWrg1em6tDtmMtgcKOBvt2T"

local request = (syn and syn.request)
    or (http and http.request)
    or http_request
    or request

assert(request, "Executor tidak mendukung HTTP request")

local response = request({
    Url = URL,
    Method = "GET",
    Headers = {
        ["Authorization"] = "Bearer " .. ACCESS_TOKEN
    }
})

assert(response and response.Body, "Request gagal")

local data = game:GetService("HttpService"):JSONDecode(response.Body)

print(data)
