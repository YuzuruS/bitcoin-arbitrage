require 'dotenv/load'
require 'slack/incoming/webhooks'

require_relative 'lib/coincheck'
require_relative 'lib/zaif'
require_relative 'lib/bitflyer'

def output msg
  if ENV['SLACK_WEBHOOK_URL'].nil?
    p msg
  else
    slack = Slack::Incoming::Webhooks.new ENV['SLACK_WEBHOOK_URL']
    slack.post msg
  end
end

def generate_stat c
  result = <<"EOS"
*#{c.service} BTC/JPY*
   bid: #{c.bid}
   ask: #{c.ask}
EOS
  result
end

def profit? trade_amount, bid, ask
  margin = ask - bid
  (trade_amount * margin).floor - ENV['MIN_VOLUME_JPY'].to_f > 0
end

def trading bidc, askc, trade_amount
  bid = bidc.bid
  ask = bidc.ask

  if profit?(trade_amount, bid, ask)
    unless bidc.has_jpy?(bid, trade_amount)
      output "*#{bidc.service} doesn't have #{(bid*trade_amount).floor}JPY*"
      return
    end

    unless askc.has_btc?(trade_amount)
      output "*#{askc.service} doesn't have #{trade_amount}BTC*"
      return
    end

    output <<"EOS"
*#{bidc.service} => #{askc.service}*
Buying  #{trade_amount}BTC #{(bid*trade_amount).floor}JPY in #{bidc.service}
Selling #{trade_amount}BTC #{(ask*trade_amount).floor}JPY in #{askc.service}
<!here> *Profit* #{((ask-bid) * trade_amount).floor}JPY
EOS
    if ENV['RUN_TRADING'] == 'on'
      bidc.buy(bid, trade_amount)
      askc.sell(ask, trade_amount)
    end
  else
    output "*#{bidc.service} => #{askc.service}*: no enough profit #{((ask-bid) * trade_amount).floor}JPY"
  end
end

def run
  trade_amount = ENV['TRADE_AMOUNT'].to_f
  output "Trading amount: #{trade_amount}BTC"
  output "Minimum valume: #{ENV['MIN_VOLUME_JPY']}JPY"

  clients = {
    :coincheck => CoincheckWrapper.new(ENV['COINCHECK_KEY'], ENV['COINCHECK_SECRET']),
    :zaif => ZaifWrapper.new(ENV['ZAIF_KEY'], ENV['ZAIF_SECRET']),
    :bitflyer => BitflyerWrapper.new(ENV['BITFLYER_KEY'], ENV['BITFLYER_SECRET'])
  }

  clients.each_value do |client|
    output generate_stat client
  end

  clients.each do |bidk, bidc|
    clients.each do |askk, askc|
      if bidk != askk
        trading bidc, askc, trade_amount
      end
    end
  end
end

if ENV['RUN_ON_HEROKU'].nil?
  loop do
    run
    sleep(5)
  end
else
  run
end
