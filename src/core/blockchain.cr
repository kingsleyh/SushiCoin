require "./blockchain/*"

module ::Sushi::Core
  class Blockchain
    getter chain : Models::Chain = Models::Chain.new
    getter current_transactions = [] of Transaction
    getter wallet : Wallet
    getter utxo : UTXO

    def initialize(@wallet : Wallet)
      @utxo = UTXO.new
      @chain.push(genesis_block)

      add_transaction(create_first_transaction([] of Models::Miner))
    end

    def push_block?(nonce : UInt64, miners : Models::Miners) : Block?
      return nil unless last_block.valid_nonce?(nonce)

      index = @chain.size.to_u32
      transactions = @current_transactions.dup

      block = Block.new(
        index,
        transactions,
        nonce,
        last_block.to_hash,
      )

      push_block?(block, miners)
    end

    def push_block?(block : Block, miners : Models::Miners) : Block?
      return nil unless block.valid_as_last?(self)

      @chain.push(block)
      record_utxo

      @current_transactions.clear
      add_transaction(create_first_transaction(miners))

      block
    end

    def replace_chain(subchain : Models::Chain) : Bool
      return false if subchain.size == 0
      return false if subchain[0].index == 0

      first_index = subchain[0].index-1
      prev_block = @chain[first_index]

      subchain.each do |block|
        return false unless block.valid_for?(prev_block)

        prev_block = block
      end

      @chain = @chain[0..first_index].concat(subchain)

      @utxo.clear
      @utxo.record(@chain)

      record_utxo

      true
    end

    def add_transaction(transaction : Transaction)
      transaction.prev_hash = if @current_transactions.size == 0
                                "0"
                              else
                                @current_transactions[-1].to_hash
                              end

      @current_transactions.push(transaction)
    end

    def get_amount_unconfirmed(address : String) : Float64
      @utxo.get_unconfirmed(address, current_transactions)
    end

    def get_amount(address : String) : Float64
      @utxo.get(address)
    end

    def last_block : Block
      @chain[-1]
    end

    def last_index : UInt32
      last_block.index
    end

    def subchain(from : UInt32)
      return nil if @chain.size < from

      @chain[from..-1]
    end

    def record_utxo
      @utxo.record(@chain)
    end

    def genesis_block : Block
      genesis_index = 0_u32
      genesis_transactions = [] of Transaction
      genesis_nonce = 0_u64
      genesis_prev_hash = "genesis"

      Block.new(
        genesis_index,
        genesis_transactions,
        genesis_nonce,
        genesis_prev_hash,
      )
    end

    def create_first_transaction(miners : Models::Miners) : Transaction
      rewards_total = Blockchain.served_amount(last_index)

      miners_nonces_size = miners.reduce(0) { |sum, m| sum + m[:nonces].size }.to_f
      miners_rewards_total = prec((rewards_total * 3.0) / 4.0)
      miners_recipients = miners.map { |m|
        amount = miners_rewards_total * (m[:nonces].size.to_f / miners_nonces_size)
        { address: m[:address], amount: amount}
      }

      node_reccipient = {
        address: @wallet.address,
        amount: prec(rewards_total - miners_recipients.reduce(0.0) { |sum, m| sum + m[:amount] }),
      }

      senders = [] of Models::Sender # No senders

      Transaction.new(
        Transaction.create_id,
        "head",
        senders,
        miners_recipients.push(node_reccipient),
        "0", # prev_hash
        "0", # sign_r
        "0", # sign_s
      )
    end

    def create_unsigned_transaction(action, senders, recipients) : Transaction
      Transaction.new(
        Transaction.create_id,
        action,
        senders,
        recipients,
        "0", # prev_hash
        "0", # sign_r
        "0", # sign_s
      )
    end

    def self.served_amount(index) : Float64
      div = (index / 10000).to_i
      return 10000.0 if div == 0
      (10000 / div).to_f
    end

    def headers
      @chain.map { |block| block.to_header }
    end

    def block_index(transaction_id : String) : UInt32?
      @utxo.index(transaction_id)
    end

    include Hashes
    include Common::Num
  end
end
