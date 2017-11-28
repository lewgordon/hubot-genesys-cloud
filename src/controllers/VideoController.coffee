
Controller = require './framework/Controller.coffee'

module.exports = class VideoController extends Controller
  @joinOrLeaveVideo: (stanza) -> (messageType) -> \
    stanza.is('message') \
      and stanza.getChild('video', 'orgspan:video')?.attrs.type is messageType

  @exposeEvents: ['videoJoin', 'videoLeave']

  @expose:
    joinVideo: (jid) ->
      @realtime.debug 'video', 'startVideoChat', jid

      type = (if jid.match(/@conference/) then 'groupchat' else 'chat')
      stanza = new ltx.Element \
        'message',
        from:@realtime.jid.bare().toString(),
        to:jid,
        type:type
  
      stanza.c \
        'video',
        xmlns:'orgspan:video',
        from:@realtime.jid.bare().toString(),
        type:'start'

      @realtime.debug 'video', 'sending join', stanza.toString()
      @realtime.send stanza

    leaveVideo: (jid) ->
      @realtime.debug 'video', 'leaveVideoChat', jid

      type = (if jid.match(/@conference/) then 'groupchat' else 'chat')
      stanza = new ltx.Element \
        'message',
        from:@realtime.jid.bare().toString(),
        to:jid,
        type: type

      stanza.c \
        'video',
        xmlns:'orgspan:video',
        from:@realtime.jid.bare().toString(),
        type:'leave'

      @realtime.debug 'video', 'sending leave', stanza.toString()
      @realtime.send stanza

  @stanzas:
    joinVideo: (stanza) -> VideoController.joinOrLeaveVideo(stanza)('start')
    leaveVideo: (stanza) -> VideoController.joinOrLeaveVideo(stanza)('leave')

  joinVideo: (stanza) ->
    room = new JID(stanza.attrs.from).bare().toString()
    from = new JID(stanza.getChild('video', 'orgspan:video').attrs.from)
      .bare().toString()
    @realtime.debug 'video', 'video join', from

    @emit 'videoJoin', { from, room }

  leaveVideo: (stanza) ->
    room = new JID(stanza.attrs.from).bare().toString()
    from = new JID(stanza.getChild('video', 'orgspan:video').attrs.from)
      .bare().toString()
    @realtime.debug 'video', 'video leave', from

    @emit 'videoLeave', { from, room }
