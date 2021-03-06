# Description:
#   Persist hubot's brain to redis
#
# Configuration:
#   REDISTOGO_URL or REDISCLOUD_URL or BOXEN_REDIS_URL or REDIS_URL.
#   URL format: redis://<host>:<port>[/<brain_prefix>]
#   If not provided, '<brain_prefix>' will default to 'hubot'.
#
# Sentinel Configuration:
#   REDIS_SENTINEL_URL is required.
#   URL format: sentinel://<host>:<port>/<master>[/<brain_prefix>]
#   If not provided, '<brain_prefix>' will default to 'hubot'.
#
#
# Commands:
#   None

Url   = require "url"
Redis = require "ioredis"

module.exports = (robot) ->
  useSentinel = if process.env.REDIS_SENTINEL_URL?
    redisUrlEnv = "REDIS_SENTINEL_URL"
    sentinelUrl = process.env.REDIS_SENTINEL_URL
    true
  else
    false

  redisUrl = if process.env.REDISTOGO_URL?
    redisUrlEnv = "REDISTOGO_URL"
    process.env.REDISTOGO_URL
  else if process.env.REDISCLOUD_URL?
    redisUrlEnv = "REDISCLOUD_URL"
    process.env.REDISCLOUD_URL
  else if process.env.BOXEN_REDIS_URL?
    redisUrlEnv = "BOXEN_REDIS_URL"
    process.env.BOXEN_REDIS_URL
  else if process.env.REDIS_URL?
    redisUrlEnv = "REDIS_URL"
    process.env.REDIS_URL
  else
    'redis://localhost:6379'

  if redisUrlEnv?
    robot.logger.info "hubot-redis-brain: Discovered redis from #{redisUrlEnv} environment variable"
  else
    robot.logger.info "hubot-redis-brain: Using default redis on localhost:6379"

  if useSentinel
    info = Url.parse sentinelUrl, true
    parts = info.path?.split('/')
    prefix = parts[2] or 'hubot'
    name = parts[1] or 'mymaster'
    sentinels = [{ host: info.hostname, port: info.port}]
    client = new Redis({
      sentinels: sentinels,
      name: name
    });
  else
    info   = Url.parse redisUrl, true
    prefix = info.path?.replace('/', '') or 'hubot'
    client = new Redis({
     host: info.hostname,
     port: info.port,
     passwd: info.auth
    });

  robot.brain.setAutoSave false

  getData = ->
    client.get "#{prefix}:storage", (err, reply) ->
      if err
        throw err
      else if reply
        robot.logger.info "hubot-redis-brain: Data for #{prefix} brain retrieved from Redis"
        robot.brain.mergeData JSON.parse(reply.toString())
      else
        robot.logger.info "hubot-redis-brain: Initializing new data for #{prefix} brain"
        robot.brain.mergeData {}

      robot.brain.setAutoSave true

  if info.auth
    client.auth info.auth.split(":")[1], (err) ->
      if err
        robot.logger.error "hubot-redis-brain: Failed to authenticate to Redis"
      else
        robot.logger.info "hubot-redis-brain: Successfully authenticated to Redis"
        getData()

  client.on "error", (err) ->
    if /ECONNREFUSED/.test err.message

    else
      robot.logger.error err.stack

  client.on "connect", ->
    robot.logger.debug "hubot-redis-brain: Successfully connected to Redis"
    getData() if not info.auth

  robot.brain.on 'save', (data = {}) ->
    client.set "#{prefix}:storage", JSON.stringify data

  robot.brain.on 'close', ->
    client.quit()
