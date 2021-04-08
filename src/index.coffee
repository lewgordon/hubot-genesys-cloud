try
  # FIXME: This is a hack for testing, otherwise instanceof doesn't work for TextMessage
  path = require('path')
  {User,Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require path.join(module.parent.path, '..')
catch
  {User,Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require 'hubot'


fs = require 'fs'
util = require 'util'
path = require 'path'
{EventEmitter} = require 'events'

global._ = require 'underscore'
_.str = require 'underscore.string'
{ client, xml } = require("@xmpp/client");
middleware = require("@xmpp/middleware");
debug = require("@xmpp/debug");

global.JID = require('@xmpp/client').jid
global.ltx = require('ltx')
global.uuid = require './lib/uuid'

config = require(path.join(process.cwd(), 'config'))

global.logError = => @robot.logger.error arguments...
global.log = => console.log arguments...
global.debug = => console.log arguments... if process.env.HUBOT_GENESYS_CLOUD_DEBUG;

class Realtime extends EventEmitter

    constructor: (client) ->
      super
      @client = client
    
    send: (stanza) ->
      debug 'stanza', 'out', stanza.toString()
      @client.send stanza
    
    jid: null
    
    debug: debug

    connected: false

    features: {}

class GenesysCloudBot extends Adapter

  options = null

  constructor: ->
    super
    @options = config

    [username, domain] = @options.username.split('@')
    @client = client({
      service: "xmpp://#{@options.host}:#{@options.port}",
      credentials: {
        authzid: @options.username,
        username,
        password: @options.password,
      },
      # This requires NODE_TLS_REJECT_UNAUTHORIZED=0
      domain,
    });

    debug(@client, true) if process.env.HUBOT_GENESYS_CLOUD_DEBUG

    @realtime = new Realtime @client

  reconnectTryCount: 0

  controllers: {}

  run: ->
    @robot.on 'error', (error) => console.error error

    @makeClient()

    @setupControllers()

    @realtime.on 'message', @_onMessage

  setupControllers: ->

    for fileName in fs.readdirSync __dirname + '/controllers'
      unless fileName.match /.*Controller(.coffee)?$/ then continue
      name = _.str.camelize(fileName.substring(0, fileName.indexOf('Controller'))).replace /^./, (m) -> m.toLowerCase()
      Controller = require "./controllers/#{fileName}"
      @controllers[name] = new Controller(@realtime)

      do (name, Controller) =>
        for funcName, func of Controller.expose
          debug 'handler', 'registering exposed controller method', funcName, 'in controller', name
          do (funcName, func) =>
            @realtime[funcName] = (args...) =>
              apply = =>
                func.apply @controllers[name], args
              unless @realtime.connected
                debug 'handle', 'deferring call to', funcName, @realtime.connected
                return @realtime.once 'connect', => 
                  debug 'handle', 'defer resolve', funcName
                  apply()
              else apply()

            null

        for event in Controller.exposeEvents
          do (name, event) =>
            @['on'+_.str.capitalize(event)] = (callback) => @on event, callback
            @controllers[name].on event, =>
              @realtime.emit event, arguments...

            null

  makeClient: ->
    @connected = false
    
    @client.on 'error', (error) => logError error
    
    @client.on 'online', @onConnect
    
    @client.on 'offline', =>
      log 'offline', arguments...
      @realtime.emit 'disconnect'
    
    @client.on 'stanza', @onStanza

    @client.on 'end', =>
      @robot.logger.info 'Connection closed, attempting to reconnect'
      @client.reconnect()

    if(@client.start)
      @client.start().catch(console.error);

  onConnect: () => 
    log '***************** online', @client.jid.toString(), @client.jid.bare().toString()
    @realtime.jid = @client.jid
    unless @realtime.connected
      @realtime.connected = true
      @emit 'connected'
    @realtime.emit 'connect'

  onStanza: (stanza) =>
    handled = false

    for name, controller of @controllers
      for func, test of controller.constructor.stanzas
        do (stanza) =>
          if test.apply(controller, [stanza])
            debug 'stanza', 'handled by', "#{controller.constructor.name}.#{func}"
            handled = true
            controller[func] stanza

    unless handled then debug 'stanza', 'unhandled'

    null

  _send: (envelope, messages, {message_fn, preferred_to_fn}) ->
    for message in messages
      unless message then continue
      if (!message_fn)
        message_fn = (msg) => msg
      transformedMessage = message_fn(message)
      @robot.logger.debug "Sending to #{envelope.room or envelope.user?.id}: #{transformedMessage}"

      if (!preferred_to_fn)
        to = envelope.room or envelope.user?.id
      else
        to = preferred_to_fn(envelope)

      @realtime.sendMessage to, transformedMessage

  send: (envelope, messages...) ->
    @_send(envelope, messages, {})

  emote: (envelope, messages...) ->
    @_send(envelope, messages, {
      message_fn: ((msg) => "/me #{msg}")
    })

  reply: (envelope, messages...) ->
    @_send(envelope, messages, {
      preferred_to_fn: ((envelope) => envelope.user?.id)
    })

  offline: =>
    @robot.logger.debug "Received offline event", @client.connect?
    @client.connect()
    clearInterval(@keepaliveInterval)
    @robot.logger.debug "Received offline event"
    @client.connect()

  leaveRoom: (res) =>
    to = res.envelope.room
    @robot.logger.debug 'Leaving room', to
    if to.match(/@conference/)
      @realtime.sendMessage to, 'Goodbye!', =>
        @realtime.leaveRoom to
        @realtime.setInactive to

  _onMessage: (msg) =>
    if msg.from is @options.username then return
    if msg.body?.match /nsfw/ then return

    if msg.type is 'person'
      user = @robot.brain.userForId msg.from
      user.room = msg.from
    else 
      user = @robot.brain.userForId msg.from
      user.room = msg.to

    @receive new TextMessage(user, msg.body)


exports.use = (@robot) ->
  new GenesysCloudBot @robot
