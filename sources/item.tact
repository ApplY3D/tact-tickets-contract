import "./message.tact";
const minTonsForStorage: Int = ton("0.02");
const gasConsumption: Int = ton("0.02");

contract NftItem {
    collection_address: Address;
    item_index: Int; 
    is_initialized: Bool;

    owner: Address?;
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


    receive(msg: Transfer){
        let ctx: Context = context();
        let custom_payload: Slice? = null;
        let from: Address? = null;
        let transfer_acticated_tickets: Int = 0;
        if(msg.custom_payload != null) {
          custom_payload = (msg.custom_payload!!).asSlice();
          from = (custom_payload!!).loadAddress();
          transfer_acticated_tickets = (custom_payload!!).loadUint(1);
          (custom_payload!!).endParse();
        }
        require(self.is_initialized == true, "not initialized");
        require(ctx.sender == self.collection_address, "Only collection can transfer");
        require(from == self.owner!!, "Invalid Owner");
        let msgValue: Int = self.msgValue(ctx.value);
        self.owner = msg.new_owner;  // change current owner to the new_owner
        if (msg.forward_amount > 0) {
            send(SendParameters{
                to: msg.new_owner,
                value: msg.forward_amount,
                mode:  SendPayGasSeparately, 
                bounce: true,
                body: OwnershipAssigned{
                    query_id: msg.query_id,
                    prev_owner: ctx.sender,
                    forward_payload: msg.forward_payload
                }.toCell()
            }); 
        }

        msgValue = msgValue - ctx.readForwardFee(); 
        if (msg.response_destination != null) { 
            send(SendParameters{ 
                to: msg.response_destination!!,
                value: msgValue - msg.forward_amount,
                mode: SendPayGasSeparately,
                bounce: true,
                body: Excesses { query_id: msg.query_id }.toCell()
            });
        } 
        
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
