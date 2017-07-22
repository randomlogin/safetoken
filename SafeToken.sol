pragma solidity ^0.4.10;
import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

contract owned {

    address public owner;
    address public ownerCandidate;
    bytes32 ownerCandidateKeyHash;

    function owned() {
        owner = msg.sender;
    }

    function acceptManagement(string key) external onlyOwnerCandidate(key) {
        owner = ownerCandidate;
    }

    function changeOwner(address candidate, bytes32 keyHash) external onlyOwner {
        ownerCandidate = candidate;
        ownerCandidateKeyHash = keyHash;
    }

    modifier onlyOwner {
        assert(owner == msg.sender);
        _;
    }

    //For security reasons ownership transfer requires hash
    modifier onlyOwnerCandidate(string key) {
        assert(msg.sender == ownerCandidate);
        assert(sha3(key) == ownerCandidateKeyHash);
        _;
    }

}

contract Token {
    uint256 public totalSupply;
    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract StandardToken is Token {

    function transfer(address _to, uint256 _value) returns (bool success) {
        if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else {
            return false;
        }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else {
            return false;
        }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
}

contract SafeToken is StandardToken, owned {

    string public constant name = "Safe Token";
    string public constant symbol = "SAFE";
    uint256 public constant decimals = 18;
    uint256 public constant maximalSupply =  1 * (10**6) * 10**decimals;

    address private constant beneficiary = 0x7Dfba43287d2847ed997DDEb1e0dE338540C60ED;
    address private constant developer = 0x63d37882D6bA050A91e76E763dC9D4aA00497Bfc; 
    bool public difficultyTickerChangeable = true;
    bool public etherPriceTickerChangeable = true;
    bool public saleActive = false;
    DifficultyTicker public difficultyTicker;
    EtherPriceTicker public etherPriceTicker;

    string public btc_difficulty;
    uint public tokenPrice;
    uint public ethUSD;
    uint public diff;

    event TokenPrice(uint tokenPrice);
    event Emission(address indexed _to, uint256 _value);

    function SafeToken(address _difficultyTicker, address _etherPriceTicker) {
        difficultyTicker = DifficultyTicker(_difficultyTicker);
        etherPriceTicker = EtherPriceTicker(_etherPriceTicker);
        calculatePrice();
    }

    //10^27 = 10^36/10^9, as the difficulty has to be divided by 10^9 and for the price in wei it's
    //needed to multiply by 10^18, which is squared equal 10^36
    function calculatePrice() {
        ethUSD = etherPriceTicker.etherUSD();
        diff = difficultyTicker.difficulty();
        tokenPrice = sqrt((10**27)*difficultyTicker.difficulty())/etherPriceTicker.etherUSD();
        TokenPrice(tokenPrice);
    }

    function openSale() onlyOwner {
        assert(!saleActive);
        saleActive = true;
    }

    function () payable external {
        require(saleActive);
        require(msg.value != 0);
        require(totalSupply < maximalSupply);
        developer.transfer(this.balance*5/100); //developer fee
        beneficiary.transfer(this.balance); //fund set up for increase of token stability and token expansion including bounty, marketing and other fees
        calculatePrice();
        uint tokens = msg.value*(10**decimals)/tokenPrice;
        totalSupply += tokens;
        assert(totalSupply+tokens > totalSupply);
        balances[msg.sender] += tokens;
        Emission(msg.sender, tokens);
    }

    //Seals current difficulty ticker and it becomes no longer changeable
    //hash parameter is added to remove the accidental possibility of sealing
    function sealDifficultyTicker(bytes32 _hash) onlyOwner {
        require(sha3(address(difficultyTicker))==_hash);
        difficultyTickerChangeable = false;
    }

    //Seals current ether price ticker and it becomes no longer changeable
    //hash parameter is added to remove the accidental possibility of sealing
    function sealEtherPriceTicker(bytes32 _hash) onlyOwner {
        require(sha3(address(etherPriceTicker))==_hash);
        etherPriceTickerChangeable = false;
    }

    function setDifficultyTicker(address _difficultyTicker) onlyOwner {
        require(difficultyTickerChangeable);
        difficultyTicker = DifficultyTicker(_difficultyTicker);
    }

    function setEtherPriceTicker(address _etherPriceTicker) onlyOwner {
        require(etherPriceTickerChangeable);
        etherPriceTicker = EtherPriceTicker(_etherPriceTicker);
    }

    //Babylonian method of calculating square root. It's qudratically convergent.
    function sqrt(uint x) internal returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

}

contract DifficultyTicker is usingOraclize, owned {

    uint providersCount;
    string[2] queries;

    string public difficultyString;
    uint public difficulty;

    event newOraclizeQuery(string description);

    function DifficultyTicker(string _query1, string _query2) {
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
        queries[0] = _query1;
        queries[1] = _query2;
        providersCount = queries.length;
        update();
    }

    function () payable {}

    //Allows to fund the ticker
    function fund() payable onlyOwner {
        update();
    }

    function update() internal {
        if (oraclize_getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            uint index = (uint(block.blockhash(10))+uint(block.blockhash(100))+now) % providersCount;
            string query = queries[index];
            oraclize_query(24 hours, "URL", query);
        }
    }

    function __callback(bytes32 myid, string result, bytes proof) {
        assert(msg.sender == oraclize_cbAddress());
        uint value = stringToUint(result);
        if (value != 0) {
            difficultyString = result;
            difficulty = value;
        }
        update();
    }

    function stringToUint(string s) internal constant returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 48 && b[i] <= 57) {
                result = result * 10 + (uint(b[i]) - 48);
            } 
            else if (b[i] == 46) {
                break;
            }
        }
        return result;
    }

}

contract EtherPriceTicker is usingOraclize, owned {

    uint providersCount;
    string[4] queries;

    string public etherUSDString;
    uint public etherUSD; //in millidollars = $0.001

    event newOraclizeQuery(string description);

    function EtherPriceTicker(string _query1, string _query2, string _query3, string _query4) {
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
        queries[0] = _query1;
        queries[1] = _query2;
        queries[2] = _query3;
        queries[3] = _query4;
        providersCount = queries.length;
        update();
    }

    function () payable {}

    //Allows to fund the ticker
    function fund() payable onlyOwner {
        update();
    }

    function update() internal {
        if (oraclize_getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            uint index = (uint(block.blockhash(10))+uint(block.blockhash(100))+now) % providersCount;
            string query = queries[index];
            oraclize_query(12 hours, "URL", query);
        }
    }

    function __callback(bytes32 myid, string result, bytes proof) {
        assert(msg.sender == oraclize_cbAddress());
        uint value = stringToUint(result);
        if (value != 0) {
            etherUSDString = result;
            etherUSD = value;
        }
        update();
    }

    function stringToUint(string s) internal constant returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 48 && b[i] <= 57) {
                result = result * 10 + (uint(b[i]) - 48);
            } 
            else if (b[i] == 46) {
                break;
            }
        }
        return result;
    }

}

