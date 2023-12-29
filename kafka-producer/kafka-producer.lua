local _M = require('apicast.policy').new('Kafka Producer', 'builtin')

local os = require('os')
local cjson = require("cjson")
local http = require("resty.http")
local inspect = require('inspect')

local assert = assert
local setmetatable = setmetatable

local new = _M.new
local mt = { __index = _M }

function _M:init()
    -- do work when nginx master process starts
    ngx.log(ngx.DEBUG, 'Passing through the init phase')
end

function _M:init_worker()
    ngx.log(ngx.DEBUG, 'Passing through the init_worker phase')
end

function _M.new(configuration)
    local self = new(configuration)

    local self = setmetatable({
        configuration = assert(configuration, 'missing proxy configuration'),
        kafka_bridge = configuration.KAFKA_BRIDGE,
        kafka_topic = configuration.KAFKA_TOPIC,
    }, mt)

    if not self.kafka_bridge or not self.kafka_topic then
        ngx.log(ngx.WARN, 'Kafka bridge or topic not specified. Data will not be sent to Kafka.')
    end

    return self
end

local function sendToKafka(self, data)
    ngx.log(ngx.INFO, 'Sending data to Kafka...')
    ngx.log(ngx.DEBUG, '\nKafka:\nKafka Bridge: ' .. self.kafka_bridge .. "\nKafka Topic: " .. self.kafka_topic .. "\nKafka URL: " .. self.kafka_bridge .. "/topics/" .. self.kafka_topic .. "\n")

    local httpc = http.new()

    local body = {
        records = {
            { value = cjson.encode(data) }
        }
    }

    local res, err = httpc:request_uri(self.kafka_bridge .. "/topics/" .. self.kafka_topic, {
        method = "POST",
        body = cjson.encode(body),
        headers = {
            ["Content-Type"] = "application/vnd.kafka.json.v2+json",
            ["Accept"] = "application/vnd.kafka.v2+json"
        }
    })

    if not res then
        ngx.log(ngx.ERR, "Failed to send data to Kafka: ", err)
        return false
    end

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Failed to send data to Kafka. Status code: ", res.status)
        return false
    end

    ngx.log(ngx.WARN, 'Data sent successfully to Kafka.')
    return true
end

function _M:rewrite()
    -- change the request before it reaches upstream
    ngx.log(ngx.DEBUG, 'Passing through the rewrite phase')
end

function _M:access()
    -- ability to deny the request before it is sent upstream
    ngx.log(ngx.DEBUG, 'Passing through the access phase')
end

function _M:content()
    -- can create content instead of connecting to upstream
    ngx.log(ngx.DEBUG, 'Passing through the content phase')
end

function _M:post_action(context)
    ngx.log(ngx.DEBUG, 'Passing through the post_action phase')
    
    local data = {}
    
    -- Request
    local request_headers = ngx.req.get_headers() or nil
    local request_headers_size = 0
    local query_param = ngx.req.get_uri_args() or nil
    local request_body_size = ngx.var.request_length or 0

    -- Check if request_headers is not nil
    if request_headers then
        -- Calculate the request headers size
        for name, value in pairs(request_headers) do
            request_headers_size = request_headers_size + #name + #value
        end
    end

    -- Response
    local response_headers = ngx.resp.get_headers() or nil
    local response_headers_size = 0
    local response_body_size = ngx.var.bytes_sent or 0

    -- Check if request_headers is not nil
    if response_headers then
        -- Calculate the request headers size
        for name, value in pairs(response_headers) do
            response_headers_size = response_headers_size + #name + #value
        end
    end

    -- Total size in bytes
    local total_size = (request_headers_size + response_headers_size + request_body_size + response_body_size)

    local service_id = ngx.var.service_id or nil

    local app_id = (ngx.ctx.context and ngx.ctx.context.current and ngx.ctx.context.current.credentials and ngx.ctx.context.current.credentials.app_id) or nil

    local user_key = (ngx.ctx.context and ngx.ctx.context.current and ngx.ctx.context.current.credentials and ngx.ctx.context.current.credentials.user_key) or nil

    local request_start_time = ngx.req.start_time() or ngx.now()

    data = {
        user_information = {
            app_id = app_id,
            user_key = user_key
        },
        request = {
            id = ngx.var.request_id,
            method = ngx.req.get_method(),
            uri = ngx.var.uri,
            query = query_param,
            headers = request_headers,
            request_headers_size = request_headers_size,
            request_body_size = request_body_size,
            start_time = os.date("%Y-%m-%d %H:%M:%S", request_start_time)
        },
        response = {
            status = ngx.status,
            headers = response_headers,
            response_headers_size = response_headers_size,
            response_body_size = response_body_size,
        },
        service_id = service_id,
        transaction_size = total_size,
        transaction_duration_time = tonumber(ngx.var.original_request_time)
    }

    -- Send data to the temporary storage asynchronously
    ngx.timer.at(0, function(premature)
        if not premature then
            sendToKafka(self, data)
        end
    end)
end

function _M:header_filter()
    -- can change response headers
    ngx.log(ngx.DEBUG, 'Passing through the header_filter phase')
end

function _M:body_filter()
    -- can read and change response body
    -- https://github.com/openresty/lua-nginx-module/blob/master/README.markdown#body_filter_by_lua
    ngx.log(ngx.DEBUG, 'Passing through the body_filter phase')
end

function _M:log()
    -- can do extra logging
    ngx.log(ngx.DEBUG, 'Passing through the log phase')
end

function _M:balancer()
    -- use for example require('resty.balancer.round_robin').call to do load balancing
    ngx.log(ngx.DEBUG, 'Passing through the balancer phase')
end

return _M
