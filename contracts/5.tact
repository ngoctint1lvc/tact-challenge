import "@stdlib/deploy";

/*
  TASK 5 - NFT random swap 
  The smart contract contains a bunch of different NFTs.
  A user brings his NFT (sends it to the smart contract), with 2.1 TON (2 for admin's profit, 0.1 for gas) in attachment (as fee for swap).
  The smart contract randomly chooses some NFT from the available NFTs (including the newly incoming one) and gives it to the user in exchange for the brought NFT (but occasionally just returns user's NFT in some cases).
  Admin can deposit NFTs without swap logic. Any NFT received from the admin is considered deposited. Admin can't swap.
  Admin can withdraw all NFTs at once, and also all TONs collected from users as fees.
  Implement getter that will return NFT addresses held by the smart contract.
  Implement getter that will return the amount of admin`s profit collected.

  In details, the smart contract (later: SC) should have this logic:
  Messages
  * AdminWithdrawalProfit 
   - SC should check that sender is the admin / otherwise throw "Insufficient privelegies"
   - SC should send all collected fees to admin except 0.1 TON (use AdminFetchProfit message as body)
     In other words: after each such operation, the contract's balance should be equal to 0.1 TON (which are reserved for storage) and the rest should be sent to the admin
  * AdminWithdrawalAllNFTs
   - SC should check that incoming tx TON value is enough for NFT withdrawal. Specifically, at least: (1 + totalNftsHeld * 0.08) TONs. Otherwise throw "Insufficent funds"
   - SC should check that sender is the admin, throw "Invalid sender" otherwise
   - If all checks pass, SC should send NFTs one by one to the admin 
   - SC should be able to withdraw all NFTs by a single message from admin
  * OwnershipAssigned 
   - if prevOwner is the owner's (admin) address, then add NFT to the collection
   - if value of TON attached is less then 2.1 TON then stop execution and return NFT back,
     but only in case that TON attached is enough to process refund without losing TONs on the SC's balance
   - randomly select NFT to send from all the NFTs that smart contract has
   - send the selected NFT to the sender with all remaining balance (except for admin profit = fees collected from this and other swaps)
     In other words: the contract's balance should increase by exactly 2 TON, some incoming TONs will be consumed for gas and the remainings of the incoming TONs should be refunded to the sender
  
  Getters
  * profit
   - returns how much collected fees is available to withdraw for the admin (all fees minus 0.1 TON)
  * nfts
   - returns dict of held NFTs with NFT indexes (sequential numbers from 0, 1, 2 ... and up to 'totalNftsHeld-1') as keys and NFT address as values 
     the order of NFTs in this dictionary doesn't matter
*/

message AdminWithdrawalProfit {
  queryId: Int as uint64;
}

message AdminWithdrawalAllNFTs {
  queryId: Int as uint64;
}

message AdminFetchProfit {
  queryId: Int as uint64;
}

message(0x05138d91) OwnershipAssigned {
    queryId: Int as uint64;
    prevOwner: Address;
    forwardPayload: Slice as remaining; 
}

message(0x5fcc3d14) Transfer { 
    queryId: Int as uint64;            
    newOwner: Address; 
    responseDestination: Address; 
    customPayload: Cell?; 
    forwardAmount: Int as coins; 
    forwardPayload: Slice as remaining; 
}

message AdminWithdrawRemainingNFTs {
    queryId: Int as uint64;
}

fun transferNft(nft: Address, value: Int, mode: Int, queryId: Int, newOwner: Address) {
    send(SendParameters {
      to: nft,
      value: value,
      mode: mode,
      bounce: true,
      body: Transfer {
          queryId: queryId,
          newOwner: newOwner,
          responseDestination: newOwner,
          customPayload: null,
          forwardAmount: 0,
          forwardPayload: emptySlice()
      }.toCell()
    });
}

contract Task5 with Deployable {
  seed: Int as uint128;
  owner: Address;
  nfts: map<Int as uint16, Address>;
  length: Int as uint16;
  saved_balance: Int as uint128;
  
  init(seed: Int, owner: Address) {
    self.owner = owner;
    self.seed = seed; // needed to deploy multiple smart contracts copies from one admin address
    self.length = 0;
    self.nfts = emptyMap();
    self.saved_balance = 0;
  }

  receive(msg: OwnershipAssigned) {
    if (msg.prevOwner == self.owner) {
      self.nfts.set(self.length, sender());
      self.length = self.length + 1;
      return;
    }

    if(context().value < ton("2.1")){
      transferNft(sender(), 0, SendRemainingValue, msg.queryId, msg.prevOwner);
      return;
    }

    nativeReserve(myBalance() - context().value + ton("2"), 0);

    let randomIdx: Int = random(0, self.length);
    transferNft(self.nfts.get(randomIdx)!!, 0, SendRemainingBalance, msg.queryId, msg.prevOwner);
    self.nfts.set(randomIdx, sender());
  }

  receive(msg: AdminWithdrawalProfit) {
    require(sender() == self.owner, "Insufficient privelegies");
    nativeReserve(ton("0.1"), 0);
    send(SendParameters{
      to: self.owner,
      value: 0,
      bounce: true,
      mode: SendRemainingBalance,
      body: AdminFetchProfit{
          queryId: msg.queryId
      }.toCell()
    });
  }

  receive(msg: AdminWithdrawRemainingNFTs) {
    let last: Bool = false;
    if (self.length <= 100) {
      last = true;
    }

    let count: Int = 0;
    while(self.length > 0 && count < 100) {
        let nft: Address = self.nfts.get(self.length - 1)!!;
        let mode: Int = SendPayGasSeparately;
        if (self.length == 1 && last) {
           nativeReserve(self.saved_balance, 0);
           mode = SendRemainingBalance;
        }
        transferNft(nft, ton("0.06"), mode, msg.queryId, self.owner);
        self.nfts.set(self.length - 1, null);
        self.length = self.length - 1;
        count = count + 1;
    }
    if (!last) {
        send(SendParameters{
            to: myAddress(),
            value: 0,
            bounce: true,
            mode: SendRemainingBalance,
            body: AdminWithdrawRemainingNFTs {
                queryId: msg.queryId
            }.toCell()
        });
    }
  }

  receive(msg: AdminWithdrawalAllNFTs) {
    require(context().value >= ton("1") + self.length * ton("0.08"), "Insufficent funds");
    require(sender() == self.owner, "Invalid sender");
    self.saved_balance = myBalance() - context().value;

    send(SendParameters {
        to: myAddress(),
        value: 0,
        bounce: true,
        mode: SendRemainingBalance,
        body: AdminWithdrawRemainingNFTs {
            queryId: msg.queryId
        }.toCell()
    });
  }

  get fun profit(): Int {
    return max(myBalance() - ton("0.1"), 0);
  }
  
  get fun nfts(): map<Int as uint16, Address> {
    return self.nfts;
  }
}
