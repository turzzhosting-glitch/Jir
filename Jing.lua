local HttpService = game:GetService("HttpService")

local URL = "https://vercel-lua-protector-preview.vercel.app/api/script"
local ACCESS_TOKEN = "R1aYKGI2EYHrRPwZIpqgOxyuMMWrg1em6tDtmMtgcKOBvt2T"

local request =
    (syn and syn.request)
    or (http and http.request)
    or http_request
    or request

assert(request, "Executor tidak menyediakan request API")

local response = request({
    Url = URL,
    Method = "GET",
    Headers = {
        ["Authorization"] = "Bearer " .. ACCESS_TOKEN
    }
})

assert(response and response.StatusCode == 200,
    "Protector request gagal: " .. tostring(response and response.StatusCode))

local payload = HttpService:JSONDecode(response.Body)

assert(payload.v == 3 and payload.alg == "AES-256-GCM",
    "Format payload tidak sesuai")

-- Di sini harus memakai implementasi AES-256-GCM
-- yang benar-benar tersedia di executor kamu.
