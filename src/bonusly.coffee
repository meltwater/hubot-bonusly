# Description:
#   Allows users to give 'micro-bonuses' on bonusly via Hubot
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_BONUSLY_ADMIN_API_TOKEN - Obtain via https://bonus.ly/api
#   HUBOT_BONUSLY_HIDE_AMOUNTS - (optional) If set, hide amounts
#   HUBOT_HIPCHAT_TOKEN - (optional) necessary for hipchat
#   HUBOT_HIPCHAT_JID - (optional) necessary for hipchat
#
# Commands:
#   hubot bonusly give <amount> to <name|email|@mention> for <reason> <#hashtag> - gives a micro-bonus to the specified user
#   hubot bonusly bonuses - lists recent micro-bonuses
#   hubot bonusly leaderboard <giver|receiver> -  show leaderboard for giving or receiving
#
# Notes:
#   To use this script, you must be signed up for Bonusly (https://bonus.ly)
#
# Author:
#   doofdoofsf

Util = require "util"

module.exports = (robot) ->
  token = process.env.HUBOT_BONUSLY_ADMIN_API_TOKEN
  adapter = robot.adapterName
  client = "hubot-#{robot.adapterName}"
  service = 'https://bonus.ly'
  bad_token_message = 'The Bonusly API token is not set. Navigate to https://bonus.ly/api as an _admin_ user (important), grab the access token and set the HUBOT_BONUSLY_ADMIN_API_TOKEN environment variable.'
  if process.env.HUBOT_HIPCHAT_JID
    badGiveMessage = "Your bonus.ly command is not on the correct format: @hubot give 100 to @receiver for reason #hashtag"
  else
    badGiveMessage = "Your bonus.ly command is not on the correct format: hubot give 100 to <name|email> for <reason> <#hashtag>"

  robot.respond /(bonusly)? bonuses/i, (msg) ->
    return msg.send bad_token_message unless token
    msg.send "o.k. I'm grabbing recent bonuses ..."
    path="/api/v1/bonuses?access_token=#{token}&limit=10"
    msg.http(service)
      .path(path)
      .get() (err, res, body) ->
        switch res.statusCode
          when 200
            data = JSON.parse body
            bonuses = data.result
            if process.env.HUBOT_BONUSLY_HIDE_AMOUNTS? && process.env.HUBOT_BONUSLY_HIDE_AMOUNTS == '1'
              bonuses_text = ("From #{bonus.giver.short_name} to #{bonus.receiver.short_name} #{bonus.reason}" for bonus in bonuses).join('\n')
            else
              bonuses_text = ("From #{bonus.giver.short_name} to #{bonus.receiver.short_name}: #{bonus.amount_with_currency} #{bonus.reason}" for bonus in bonuses).join('\n')
            msg.send bonuses_text
          when 400
            data = JSON.parse body
            msg.send data.message
          else
            msg.send "Request (#{service}#{path}) failed (#{res.statusCode})."

  robot.respond /(bonusly)? ?leaderboard ?(giver|receiver)?/i, (msg) ->
    return msg.send bad_token_message unless token
    type_str = msg.match[2]
    type = if (type_str? && type_str == 'giver') then 'giver' else 'receiver'
    path="/api/v1/analytics/standouts?access_token=#{token}&role=#{type}&limit=10"
    msg.send "o.k. I'll pull up the top #{type}s for you ..."
    msg.http(service)
      .path(path)
      .get() (err, res, body) ->
        switch res.statusCode
          when 200
            leaders = JSON.parse(body).result
            leaders_text = ("##{index+1} with #{leader.count} bonuses: #{leader.user.first_name} #{leader.user.last_name}" for leader, index in leaders).join('\n')
            msg.send leaders_text
          when 400
            data = JSON.parse body
            msg.send data.message
          else
            msg.send "Request (#{service}#{path}) failed (#{res.statusCode})."


  robot.respond /(bonusly)?\s*give\s+(.*)+/i, (msg) ->
    return msg.send bad_token_message unless token
    if process.env.HUBOT_HIPCHAT_JID
      giver = msg.message.user.email_address
    else
      giver = msg.message.user.name.toLowerCase()

    text = msg.match[2]
    return msg.send badGiveMessage unless text?

    # are we using the hipchat adapter
    if process.env.HUBOT_HIPCHAT_JID
      receiverIdentifier = null
      textPattern = /(\d+)\s+to\s+@(\w+)\s+for\s+(.*)+\s?/i

      matches = text.match(textPattern)
      return msg.send badGiveMessage unless matches?

      [ amount, receiverMention, reason ] = matches[1..3]

      return msg.send badGiveMessage if !amount? || !receiverMention? || !reason?

      receiverIdentifier = null

      if process.env.HUBOT_HIPCHAT_TOKEN
        msg.http("https://api.hipchat.com")
          .path("/v2/user/@#{receiverMention}?auth_token=#{process.env.HUBOT_HIPCHAT_TOKEN}")
          .get() (err, res, body) ->
            switch res.statusCode
              when 200
                console.log(JSON.parse(body))
                receiverIdentifier = JSON.parse(body).email
                text = "+#{amount} to #{receiverMention} for #{reason}"
                msg.send "o.k. I'll try to give that bonus ..."
                path = '/api/v1/bonuses?'
                params = "access_token=#{token}&giver_email=#{encodeURIComponent(giver)}&receiver_email=#{encodeURIComponent(receiverIdentifier)}&amount=#{amount}&reason=#{encodeURIComponent(text)}"
                console.log(path+params)
                msg.http(service)
                  .path(path)
                  .header('Content-Type', 'application/x-www-form-urlencoded')
                  .post(params) (err, res, body) ->
                    switch res.statusCode
                      when 200
                        data = JSON.parse body
                        console.log data
                        return msg.send "You just gave #{data.result.amount} Kudo bonus to #{data.result.receiver.email}. You have #{data.result.giver.giving_balance} Kudos remaining for this month."
                      when 400
                        data = JSON.parse body
                        return msg.send data.message
                      else
                        console.log "Failed to give bonus: (#{res.statusCode}). Tried to post (#{params}) to (#{service}#{path})"
                        return msg.send "Failed to give bonus: (#{res.statusCode}). Tried to post to (#{service}#{path}), the service is probably down or too slow."
              else
                return msg.send "Request to check receiver hipchat email failed (#{res.statusCode})."
      else
        return msg.send "Please set your hubot hipchat token HUBOT_HIPCHAT_TOKEN ."

    else
      msg.send "o.k. I'll try to give that bonus ..."
      path = '/api/v1/bonuses/create_from_text'
      params = "access_token=#{token}&giver=#{encodeURIComponent(giver)}&client=#{encodeURIComponent(client)}&text=#{encodeURIComponent(text)}"

      msg.http(service)
        .path(path)
        .header('Content-Type', 'application/x-www-form-urlencoded')
        .post(params) (err, res, body) ->
          switch res.statusCode
            when 200
              data = JSON.parse body
              return msg.send "You just gave #{data.result.amount} Kudo bonus to #{data.result.receiver.email}. You have #{data.result.giver.giving_balance} Kudos remaining for this month."
            when 400
              data = JSON.parse body
              return msg.send data.message
            else
              return msg.send "Failed to give: (#{res.statusCode}). Tried to post (#{params}) to (#{service}#{path})"
