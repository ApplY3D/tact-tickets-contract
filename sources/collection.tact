import "@stdlib/ownable";
import "./item.tact";
import "./message.tact";

contract NftCollection with Ownable {
    next_item_index: Int as uint32 = 0;
    owner: Address;
    royalty_params: RoyaltyParams?;                      
    collection_content: Cell;
    event_ended: Bool = false;

    init(owner: Address, collection_content: Cell, royalty_params: RoyaltyParams){
        self.owner = owner;
        self.collection_content = collection_content; 
        self.royalty_params = royalty_params;
    }

    receive("Event ended") {
        self.requireOwner();
        self.event_ended = true;
    }

    receive(msg: RequestMintNft){
        self.requireOwner();
        let ctx: Context = context(); // get sender Info
        let msgValue: Int = ctx.value;
        let tonBalanceBeforeMsg: Int = myBalance() - msgValue;
        let storageFee: Int = minTonsForStorage - min(tonBalanceBeforeMsg, minTonsForStorage);
        msgValue = msgValue - (storageFee + gasConsumption);
        self.mint(ctx.sender, msg.owner, msg.content, msgValue);

        emit(LogEventMintRecord{ minter: sender(), item_id: self.next_item_index, generate_number: nativeRandom() }.toCell());
    }


    receive(msg: GetIsEventEnded) {
        send(SendParameters{
            to: sender(),
            value: 0,
            mode: SendRemainingValue,
            bounce: false,
            body: ReportIsEventEnded { query_id: msg.query_id, event_ended: self.event_ended }.toCell()
        });
    }

    // ===== Private Methods ===== //
    fun mint(sender: Address, owner: Address, content: Cell?, msgValue: Int) {
        require(self.next_item_index >= 0, "non-sequential NFTs");
        let nft_init: StateInit = self.getNftItemInit(self.next_item_index);
        send(SendParameters{
                to: contractAddress(nft_init), 
                value: msgValue, 
                bounce: false,
                mode: SendIgnoreErrors,
                body: NftDeploy{
                    index: self.next_item_index,
                    owner: owner,
                    content: content,
                }.toCell(),
                code: nft_init.code,
                data: nft_init.data
            });
        send(SendParameters{ 
            to: sender,
            value: 0,
            mode: SendRemainingValue,
            bounce: true,
            body: Excesses { query_id: 1 }.toCell()
        });
        // dump(self.next_item_index); // Reference at: https://tact-by-example.org/03-emit
        self.next_item_index = self.next_item_index + 1;
    }

    receive(msg: GetRoyaltyParams) {   
        let ctx: Context = context(); // get sender Info
        send(SendParameters{
            to: ctx.sender,
            value: 0,
            mode: 64, 
            bounce: false,
            body: ReportRoyaltyParams {
                query_id: msg.query_id,
                numerator:  (self.royalty_params!!).numerator,
                denominator: (self.royalty_params!!).denominator,
                destination: self.owner
            }.toCell()
        });        
    }

    // ------------------ Get Function  ------------------ //
    get fun get_collection_data(): CollectionData {     
        let b: StringBuilder = beginString();
        let collectionDataString: String = self.collection_content.asSlice().asString();
        b.append(collectionDataString);
        b.append("meta.json"); // You can changed this your self.
        return CollectionData{
            next_item_index: self.next_item_index, 
            collection_content: b.toCell(), 
            owner_address: self.owner
        };
    }

    get fun get_nft_address_by_index(item_index: Int): Address?{      
        let initCode: StateInit = self.getNftItemInit(item_index);
        return contractAddress(initCode);
    }

    get fun getNftItemInit(item_index: Int): StateInit {
        return initOf NftItem(myAddress(), item_index);
    }
    
    get fun get_nft_content(index: Int, individual_content: Cell): Cell { 
        let b: StringBuilder = beginString();
        let ic: String = individual_content.asSlice().asString();
        b.append(ic);
        return b.toCell();
    }

    get fun royalty_params(): RoyaltyParams {
        return self.royalty_params!!;
    }
}

