import "./message.tact";
const minTonsForStorage: Int = ton("0.02");
const gasConsumption: Int = ton("0.02");

contract NftItem {
    collection_address: Address;
    item_index: Int; 
    is_initialized: Bool;

    owner: Address?;
    is_activated: Bool = false;
    current_transfer: Transfer?;
    individual_content: Cell?;

    init(collection_address: Address, item_index: Int){
        require(sender() == collection_address, "not from collection");
        self.collection_address = collection_address;
        self.item_index = item_index;
        self.is_initialized = false;
    }

    receive(msg: NftDeploy) {
        require(sender() == self.collection_address, "Invalid Sender");
        require(self.item_index == msg.index, "Invalid Index");
        require(!self.is_initialized, "Already Deployed");
        self.owner = msg.owner;
        self.individual_content = msg.content;
        self.is_initialized = true;
    }

    receive(msg: ReportIsEventEnded) {
        let ctx: Context = context();
        require(ctx.sender == self.collection_address, "Invalid Sender");
        require(self.is_activated == false || msg.event_ended == true, "Transferable only if event ended or not activated");

        require(self.current_transfer != null, "Current transfer is null");
        require((self.current_transfer!!).new_owner != null, "Next owner is null");
        let current_transfer: Transfer = self.current_transfer!!;
        self.current_transfer = null;
        self.owner = current_transfer.new_owner;
        if (current_transfer.forward_amount > 0) {
            send(SendParameters{
                to: current_transfer.new_owner,
                value: current_transfer.forward_amount,
                mode:  SendPayGasSeparately, 
                bounce: true,
                body: OwnershipAssigned{
                    query_id: current_transfer.query_id,
                    prev_owner: self.owner!!,
                    forward_payload: current_transfer.forward_payload
                }.toCell()
            }); 
        }
        let msgValue: Int = self.msgValue(ctx.value);
        msgValue = msgValue - ctx.readForwardFee(); 
        if (current_transfer.response_destination != null) { 
            send(SendParameters{ 
                to: current_transfer.response_destination!!,
                value: msgValue - current_transfer.forward_amount,
                mode: SendPayGasSeparately,
                bounce: true,
                body: Excesses { query_id: current_transfer.query_id }.toCell()
            });
        }
    }

    receive(msg: Transfer){
        let ctx: Context = context();
        require(self.is_initialized == true, "not initialized");
        require(ctx.sender == self.owner!!, "Invalid Owner");
        require(self.current_transfer == null, "Current transfer is not null");
        let msgValue: Int = self.msgValue(ctx.value);
        self.current_transfer = msg;
        send(SendParameters{ 
            to: self.collection_address,
            value: msgValue,
            mode: SendPayGasSeparately,
            bounce: true,
            body: GetIsEventEnded { query_id: msg.query_id }.toCell()
        });
    }
    
    receive(msg: GetStaticData){ 
        let ctx: Context = context();
        send(SendParameters {
            to: ctx.sender,
            value: 0,
            mode: 64,  // (return msg amount except gas fees) 
            bounce: true,
            body: ReportStaticData{
                query_id: msg.query_id,
                index_id: self.item_index,
                collection: self.collection_address
            }.toCell()
        });
    }

    fun msgValue(value: Int): Int {
        let tonBalanceBeforeMsg: Int = myBalance() - value;
        let storageFee: Int = minTonsForStorage - min(tonBalanceBeforeMsg, minTonsForStorage);
        return value - (storageFee + gasConsumption);
    }

    // --------- Get Function  --------- //
    get fun get_nft_data(): GetNftData {
        let b: StringBuilder = beginString();
        let collectionData: String = (self.individual_content!!).asSlice().asString();
        b.append(collectionData);
        b.append(self.item_index.toString());
        b.append(".json");

        return GetNftData {
            is_initialized: self.is_initialized, 
            index: self.item_index, 
            collection_address: self.collection_address, 
            owner_address: self.owner!!,
            individual_content: b.toCell()
        };
    }
}
