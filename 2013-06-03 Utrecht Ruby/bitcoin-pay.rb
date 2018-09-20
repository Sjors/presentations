#!/usr/bin/env ruby
require 'open-uri'
require 'JSON'
require 'digest/sha2'
require 'pry'
require 'bigdecimal'
require 'bitcoin' # Because I need to cheat every now and then

# Usage:
# gem install pry json ffi ruby-bitcoin
# ruby bitoin-pay.rb YOUR_ADDRESS YOUR_PRIVATE_KEY

# The private key should be in wallet import format, i.e. start with 5. That's
# usually the case for a paper wallet. If you have a Blockchain wallet, open and
# select "paper wallet" to find your private key. 

@recipient = "1KHxSzFpdm337XtBeyfbvbS9LZC1BfDu8K" # Purple Dunes (replace with an address you own)

@amount = BigDecimal.new("0.01") # Bitcoins. Never use floats when dealing with money.

# Caveats:
# * Don't use this with an address that has a lot of bitcoins on it and clear
#   your bash history afterwards: history -c
# * this will not work if you recently received bitcoins in a non-standard way
#   (e.g. https://en.bitcoin.it/wiki/Script#Transaction_puzzle)
# * this code is just for education, for your own projects you should use 
#   something like https://github.com/lian/bitcoin-ruby

SATOSHI_PER_BITCOIN = BigDecimal.new("100000000") # (1 BTC = 100,000,000 Satoshi)

@sender = ARGV[0]
@secret_wif = ARGV[1]

# https://en.bitcoin.it/wiki/Transaction_fees
@transaction_fee = @amount >=  BigDecimal.new("0.01") ?  BigDecimal.new("0") :  BigDecimal.new("0.0005") 
puts "About to send #{ @amount.to_f } bitcoins from #{ @sender[0..5] }... to #{ @recipient[0..5] }... " + (@transaction_fee > 0 ? "plus a #{ @transaction_fee.to_f } transaction fee." : "") 

# Obtain the current balance and most recent transactions for sender:
puts "Fetching the current balance for #{@sender[1..5]} from blockchain.info..."
url = "https://blockchain.info/address/#{ @sender }?format=json"

res = JSON.parse(open(url).read)
@balance = BigDecimal.new(res["final_balance"]) / SATOSHI_PER_BITCOIN
  
puts "Current balance of sender: #{ @balance.to_f } BTC"

raise "Insuffient funds" if @balance < @amount + @transaction_fee

# Just knowing that the balance is sufficient is not enough. Just like with real
# money your balance is the result of one or more incoming payments. But unlike
# real money, you need specify exactly which of these payments you wish to spend.
# In addition you need spend that entire payment and send yourself the change.

# For example if I earned 0.5 BTC two days ago, bought dinner for 0.1 BTC
# yesterday and then received another 0.3 BTC today, my balance is 0.7 BTC.
# When I bought dinner, I paid 0.5 BTC of which 0.1 went to the restaurant
# and 0.4 went back as change. If I now want to spend 0.39 BTC I would
# need the last transaction and send myself 0.01 change. Alternatively I could 
# take the last two transactions (0.4 + 0.3) and send myself 0.31 change.
# If I need to spend 0.41 bitcoins, I have no choice but to combine both
# previous transactions.

# Normally you would download the entire blockchain for this, but in stead we
# used a webservice to fetch just the information we need.

url = "https://blockchain.info/unspent?active=#{ @sender }&format=json"
res = JSON.parse(open(url).read)
@unspent_outputs = res["unspent_outputs"]

# We'll continue adding previous payments until we have enough:

@inputs = []

input_total = BigDecimal.new("0")
@unspent_outputs.each do |output|
    @inputs <<  {
      previousTx: [output["tx_hash"]].pack("H*").reverse.unpack("H*")[0], # Reverse
      index: output["tx_output_n"],
      scriptSig: nil # We'll sign it later
    }
    amount = BigDecimal.new(output["value"]) / SATOSHI_PER_BITCOIN
    puts "Using #{amount.to_f} from output #{output["tx_output_n"]} of transaction #{output["tx_hash"][0..5]}..."
    input_total += amount
    break if input_total >= @amount + @transaction_fee
end

@change = input_total - @transaction_fee - @amount

puts "Spend #{@amount.to_f} and return #{ @change.to_f } as change."

raise "Unable to process inputs for transaction" if input_total < @amount + @transaction_fee || @change < 0

# The address is written in Base58. This consist of all letters and numbers,
# but without certain ambigious ones (1l, 0Oo, etc). That leaves these 58:
#  "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
# Don't just use any library that claims to do Base58 conversion, because 
# Bitcoin uses a custom form of Base58: 
# https://en.bitcoin.it/wiki/Base58Check_encoding
# In particular a gem like base58_gmp gem seems to 
# ignore leading zero's, which is dangerous with Bitcoin.

# I'm going to cheat here and use ruby-bitcoin built in conversion method:
sender_hex = Bitcoin.decode_base58(@sender)
recipient_hex = Bitcoin.decode_base58(@recipient)

# All bitcoins on the sender address must be used as the input for the transaction. 
# After substracting the amount to transfer and transaction fee, the change 
# is returned to the sender, through a second output.

@outputs = [ 
  { # Amount to transfer (leave out the leading zeros and 4 byte checksum)
      value: @amount, 
      scriptPubKey: "OP_DUP OP_HASH160 " + (recipient_hex[2..-9].size / 2).to_s(16) + " " + recipient_hex[2..-9] + " OP_EQUALVERIFY OP_CHECKSIG "
      # OP_DUP, etc is the default payment script: https://en.bitcoin.it/wiki/Script 
    }
]

if @change > 0
  @outputs << { 
    value: @change, 
    scriptPubKey: "OP_DUP OP_HASH160 " + (sender_hex[2..-9].size / 2).to_s(16) + " " + sender_hex[2..-9] + " OP_EQUALVERIFY OP_CHECKSIG "
  }
  
end   
  
# The difference between inputs and outputs is the transaction fee, which goes to the miners.
  

# We still need to sign the inputs (for which we need the outputs):
# https://en.bitcoin.it/wiki/Transactions
# https://en.bitcoin.it/wiki/Technical_background_of_Bitcoin_addresses
# https://en.bitcoin.it/wiki/Scripts
#
# The input script is described as <sig> <pubKey>

# <pubKey> is such that OP_HASH(pubKey) == sender_hex
# OP_HASH according to the wiki is SHA256 followed by RIPEMD-160.
# In reality however, it involves steps 2-8 in the address generation 
# process, which do few extra things.
# 
# @sender is step 9 in the bitcoin address generation process  
# sender_hex is step 8
#
# Example: https://blockchain.info/nl/tx/d6d62745bb4d15d3ef8ff1aaecef5bc7a794e77f3257516edd3ebe5ada659ae4
# incoming script has public key: "04f4023d13d2fc50a1f9e0d81bcd2d2f6eabc582df580c54bc2a998395a95e5107dea6f93d878eb7453dd93f0c6b4f2fa285321596152a5b2144681e57182f1186"
# for the receiving address (14DCzMesaa1xUCb87Dp3qC1oF7nwmS7LA5)
# We can verify this: 
#
# step_2 = (Digest::SHA2.new << [pubKey].pack("H*")).to_s        -> bb905b336...
# step_3 = (Digest::RMD160.new << [step_2].pack("H*")).to_s      -> 23376070c...
# step_4 = "00" + step_3
# step_5 = (Digest::SHA2.new << [step_4].pack("H*")).to_s     
# step_6 = (Digest::SHA2.new << [step_5].pack("H*")).to_s
# step_7 = step_7 = step_6[0..7]  ->  b18a9aba
# step_8 = step_4 + step_7        ->  00233760...b18a9aba 
# step_9 = Bitcoin.encode_base58(step_8)  -> 14DCzMe... which is the bitcoin address

# Starting from the bitcoin address, we can't reverse step 9 to step 2 to get
# the public key. Also we can only get the <pubKey> out of the blockchain 
# like in the example above if it's been used before to send money. 
# This is why we need the private key, so we can perform step 1.

# The @secret provided as input is in Wallet   Format:
# https://en.bitcoin.it/wiki/Wallet_import_format
# We need to convert it (basically just removing the checksum):

w2 = Bitcoin.decode_base58(@secret_wif)
w3 = w2[0..-9]
@secret = w3[2..-1]

# Unfortunately it's quite easy to generate a new secp256k1 keypair in ruby,
# but not to just get a public key given a private key. We need to cheat here
# and use the Bitcoin gem to create an OpenSSL_EC keypair object from our
# public and private key strings. OpenSSL_EC itself is not part of that gem, 
# it's part of ruby-openssl

@keypair = Bitcoin.open_key(@secret)
raise "Invalid keypair" unless @keypair.check_key

# Now that we know the public key, we can figure out the corresponding address.
# We then check that address with the input to this script (which was redundant).

step_2 = (Digest::SHA2.new << [@keypair.public_key_hex].pack("H*")).to_s
step_3 = (Digest::RMD160.new << [step_2].pack("H*")).to_s 
step_4 = "00" + step_3
step_5 = (Digest::SHA2.new << [step_4].pack("H*")).to_s     
step_6 = (Digest::SHA2.new << [step_5].pack("H*")).to_s
step_7 = step_7 = step_6[0..7]  
step_8 = step_4 + step_7   
step_9 = Bitcoin.encode_base58(step_8) 

raise "Public key does not match private key" if @sender != step_9

puts "Public key matches private key, so we can sign the transaction..."

# It wouldn't be very safe if all you needed for payment was the public key,
# since that becomes public knowledge as soon as you make 1 transaction. In
# addition, someone might mess with the destination of the transaction. 
# That's why we sign the outputs using the private key.
# In order for others to verify that signature, they need to know our public key. 
# They then know for sure that we wanted this transaction to take place. And
# because a public key can also be converted to an address, they can check
# if we are actually allowed to spend those bitcoins (our address is written 
# in the outputs of the earlier transactions that we are now using as inputs).

# https://en.bitcoin.it/w/images/en/7/70/Bitcoin_OpCheckSig_InDetail.png
# http://bitcoin.stackexchange.com/questions/3374/how-to-redeem-a-basic-tx

# Temporary value for signing purposes. Normally you
# should obtain the actual scriptSig from each of the outputs,
# but Blockchain (json) doesn't give us that. We're just guessing
# that it's the default. This is why this script won't 
# work for non-standard transactions.
# The scriptsig uses the address in hex, but without the leading 00 and 4 
# byte checksum at the end.

scriptSig = "OP_DUP OP_HASH160 " + (sender_hex[2..-9].size / 2).to_s(16) + " " + sender_hex[2..-9] + " OP_EQUALVERIFY OP_CHECKSIG "

@inputs.collect!{|input|
  {
    previousTx: input[:previousTx],
    index: input[:index],
    # Add 1 byte for each script opcode:
    scriptLength: sender_hex[2..-9].length / 2 + 5, 
    scriptSig: scriptSig, 
    
    sequence_no: "ffffffff" # Ignored
  }
} 

@transaction = {
  version: 1,
  in_counter: @inputs.count,
  inputs: @inputs,
  out_counter: @outputs.count,
  outputs: @outputs,
  lock_time: 0,
  # Step 13, but don't use this when signing with BitcoinQT
  hash_code_type: "01000000" # Temporary value used during the signing process 
}

# Now let's serialize and create the input signatures. We then add these signatures
# back into the transaction and serialize it again.

puts "Readable version of the transaction (numbers in strings are hex, otherwise decimal)\n\n"
pp @transaction

def little_endian_hex_of_n_bytes(i, n) 
  i.to_s(16).rjust(n * 2,"0").scan(/(..)/).reverse.join()
end

def parse_script(script)
  script.gsub("OP_DUP", "76").gsub("OP_HASH160", "a9").gsub("OP_EQUALVERIFY", "88").gsub("OP_CHECKSIG", "ac")
end

def serialize_transaction(transaction)
  tx = ""
  # Little endian 4 byte version number: 1 -> 01 00 00 00
  tx << little_endian_hex_of_n_bytes(transaction[:version],4) + "\n"
  # You can also use: transaction[:version].pack("V") 

  # Number of inputs
  tx << little_endian_hex_of_n_bytes(transaction[:in_counter],1) + "\n"

  transaction[:inputs].each do |input|
    tx << little_endian_hex_of_n_bytes(input[:previousTx].hex, input[:previousTx].length / 2) + " "
    tx << little_endian_hex_of_n_bytes(input[:index],4) + "\n"
    tx << little_endian_hex_of_n_bytes(input[:scriptLength],1) + "\n"
    tx << parse_script(input[:scriptSig]) + " "
    tx << input[:sequence_no] + "\n"
  end
  
  # Number of outputs
  tx << little_endian_hex_of_n_bytes(transaction[:out_counter],1) + "\n"
  
  transaction[:outputs].each do |output|
    tx << little_endian_hex_of_n_bytes((output[:value] * SATOSHI_PER_BITCOIN).to_i,8) + "\n"
    unparsed_script = output[:scriptPubKey]
    # Parse the script commands into hex opcodes (yes this is lame):
    tx << little_endian_hex_of_n_bytes(parse_script(unparsed_script).gsub(" ", "").length / 2, 1) + "\n"
    tx << parse_script(unparsed_script) + "\n"
  end
  
  tx << little_endian_hex_of_n_bytes(transaction[:lock_time],4) + "\n"
  tx << transaction[:hash_code_type] # This is empty after signing
  tx
end
 
@utx = serialize_transaction(@transaction)

puts "\nHex unsigned transaction:"
puts @utx

# Remove line breaks and spaces
@utx.gsub!("\n", "")
@utx.gsub!(" ", "")

# Sha256 has it twice and then sign

sha_first = (Digest::SHA2.new << [@utx].pack("H*")).to_s
sha_second = (Digest::SHA2.new << [sha_first].pack("H*")).to_s

# # The BitcoinQT stores the hash as a uint256, which is then casted to a char.
# # So we need to convert our hash from big to little endian:
# 
# sha_little_endian = little_endian_hex_of_n_bytes(sha_second.hex,  32)

# signature_binary = @keypair.dsa_sign_asn1([sha_little_endian].pack("H*"))

puts "\nHash that we're going to sign: #{sha_second}"

signature_binary = @keypair.dsa_sign_asn1([sha_second].pack("H*"))

signature = signature_binary.unpack("H*").first

hash_code_type = "01"
signature_plus_hash_code_type_length = little_endian_hex_of_n_bytes((signature + hash_code_type).length / 2, 1)
pub_key_length = little_endian_hex_of_n_bytes(@keypair.public_key_hex.length / 2, 1)

scriptSig = signature_plus_hash_code_type_length + " " + signature + " "  + hash_code_type + " "  + pub_key_length + " " + @keypair.public_key_hex

# Replace scriptSig and scriptLength for each of the inputs:
@transaction[:inputs].collect!{|input| 
  {
    previousTx:   input[:previousTx],
    index:        input[:index],
    scriptLength: scriptSig.gsub(" ","").length / 2,
    scriptSig:    scriptSig,
    sequence_no:  input[:sequence_no]
  }
}

@transaction[:hash_code_type] = ""

@tx = serialize_transaction(@transaction)

# Debug:
# puts "\nHex signed transaction with line-breaks:\n\n"
# puts @tx

# Remove line breaks and spaces
@tx.gsub!("\n", "")
@tx.gsub!(" ", "")

puts "\nHex signed transaction: (#{ @tx.size / 2 } bytes)\n\n"
puts @tx

puts "\nCopy paste the transaction and transmit it at https://blockchain.info/pushtx\n"