import "@stdlib/deploy";

/*
  TASK 2 - Proxy 
  Create a contract that forwards all received TONs
  to the admin contract (whose address is set in init_store).
  Message from this proxy contract to the admin contract should contain:
    - Address of user who sent original message (should be stored in the outcoming body's data/bits)
    - Original message that proxy smart contract received from user (should be stored in the outcoming body's first ref)
  Also, if admin contract decides to reject message (if it sends to the proxy "Refund" message with opcode=0x44),
  proxy contract needs to forward all TONs (attached to Refund message) back to the user.
  User address will be provided in Refund message body as "sender".
  In refund transaction, it is important to have a check that the refund message came from the admin address
*/

message(0x44) Refund {
  queryId: Int as uint64;
  sender: Address;
}

contract Task2 with Deployable {
  admin: Address;

  init(admin: Address) {
    self.admin = admin;
  }
  
  receive(msg: Refund) {
    require(sender() == self.admin, "Error");

    send(
        SendParameters {
            value: 0,
            bounce: false,
            to: msg.sender,
            mode: SendIgnoreErrors + SendRemainingBalance
        }
    );
  }

  receive(msg: Slice) {
    send(
        SendParameters {
            value: context().value,
            bounce: false,
            to: self.admin,
            mode: SendIgnoreErrors + SendRemainingBalance,
            body: beginCell()
                .storeRef(
                    beginCell().storeSlice(msg).asCell()
                )
                .storeAddress(
                    sender()
                )
                .asCell()
        }
    );
  }
}
