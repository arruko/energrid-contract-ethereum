// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

// Custom errors for gas optimization
error InvalidAddress();
error InvalidAmount();
error ExceedsMaxSupply();
error Unauthorized();
error ReentrantCall();
error ContractPaused();
error ContractNotPaused();
error InvalidDeadline();
error TradeNotActive();
error DeadlinePassed();
error InsufficientEscrow();
error TransferFailed();
error TokenDoesNotExist();
error CertificateAlreadyRevoked();
error CertificateIsRevoked();
error AlreadyRegistered();
error NotRegistered();
error NotContract();
error EmptyMetadata();
error InvalidSignature();
error NoActiveDispute();
error TradeInDispute();
error ExceedsAgreedAmount();
error ReasonRequired();
error DecisionRequired();
error InvalidBatchId();
error NumericOverflow();
error SameAddress();
error DeadlineNotReached();
error InvalidTokenAddress();
error BatchSizeLimit();
error ArrayLengthMismatch();
error InvalidCommitment();
error CommitmentTooEarly();

/// @title ReentrancyGuard - Optimized reentrancy protection
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/// @title Pausable - Optimized pause functionality
abstract contract Pausable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        if (paused()) revert ContractPaused();
        _;
    }

    modifier whenPaused() {
        if (!paused()) revert ContractNotPaused();
        _;
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

/// @title kWhToken - Optimized ERC20 Token for energy units
contract kWhToken is ERC20, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public totalMinted;
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || super.supportsInterface(interfaceId);
    }

    event TokensMinted(address indexed to, uint256 amount);
    event BatchTokensMinted(address[] indexed recipients, uint256[] amounts, uint256 totalMinted);

    constructor() ERC20("Kilowatt Hour Token", "kWh") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert InvalidAddress();
        
        uint256 newTotal;
        unchecked {
            newTotal = totalMinted + amount;
        }
        if (newTotal > MAX_SUPPLY || newTotal < totalMinted) revert ExceedsMaxSupply();
        
        totalMinted = newTotal;
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /// @notice Mint tokens to multiple recipients in a single transaction
    function mintBatch(address[] calldata recipients, uint256[] calldata amounts) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
    {
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length > 50) revert BatchSizeLimit(); // Prevent gas limit issues
        
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length;) {
            totalAmount += amounts[i];
            unchecked { ++i; }
        }
        
        uint256 newTotal;
        unchecked {
            newTotal = totalMinted + totalAmount;
        }
        if (newTotal > MAX_SUPPLY || newTotal < totalMinted) revert ExceedsMaxSupply();
        
        totalMinted = newTotal;
        
        for (uint256 i = 0; i < recipients.length;) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            _mint(recipients[i], amounts[i]);
            unchecked { ++i; }
        }
        
        emit BatchTokensMinted(recipients, amounts, totalAmount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
}

/// @title Energy1155 - Optimized Multi-token for kWh + CEL
contract Energy1155 is ERC1155, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant KWH_ID = 1;
    uint256 public constant CEL_ID = 2;

    // Optimized struct packing for 1 storage slot
    struct SupplyData {
        uint128 maxSupply;
        uint128 totalSupply;
    }

    mapping(uint256 => SupplyData) public supplyData;

    constructor(string memory uri) ERC1155(uri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        supplyData[KWH_ID] = SupplyData(uint128(1_000_000_000 * 10**18), 0);
        supplyData[CEL_ID] = SupplyData(1_000_000, 0);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function mintKWh(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert InvalidAddress();
        
        SupplyData storage data = supplyData[KWH_ID];
        uint128 newTotal;
        unchecked {
            newTotal = data.totalSupply + uint128(amount);
        }
        if (newTotal > data.maxSupply || newTotal < data.totalSupply) revert ExceedsMaxSupply();
        
        data.totalSupply = newTotal;
        _mint(to, KWH_ID, amount, "");
    }

    function mintCEL(address to, uint256 quantity) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert InvalidAddress();
        
        SupplyData storage data = supplyData[CEL_ID];
        uint128 newTotal;
        unchecked {
            newTotal = data.totalSupply + uint128(quantity);
        }
        if (newTotal > data.maxSupply || newTotal < data.totalSupply) revert ExceedsMaxSupply();
        
        data.totalSupply = newTotal;
        _mint(to, CEL_ID, quantity, "");
    }

    /// @notice Batch mint both kWh and CEL tokens efficiently
    function mintBatch(
        address to,
        uint256[] calldata amounts
    ) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert InvalidAddress();
        if (amounts.length != 2) revert ArrayLengthMismatch();
        
        uint256[] memory ids = new uint256[](2);
        ids[0] = KWH_ID;
        ids[1] = CEL_ID;
        
        // Update supply data
        SupplyData storage kwhData = supplyData[KWH_ID];
        SupplyData storage celData = supplyData[CEL_ID];
        
        uint128 newKwhTotal;
        uint128 newCelTotal;
        
        unchecked {
            newKwhTotal = kwhData.totalSupply + uint128(amounts[0]);
            newCelTotal = celData.totalSupply + uint128(amounts[1]);
        }
        
        if (newKwhTotal > kwhData.maxSupply || newKwhTotal < kwhData.totalSupply) revert ExceedsMaxSupply();
        if (newCelTotal > celData.maxSupply || newCelTotal < celData.totalSupply) revert ExceedsMaxSupply();
        
        kwhData.totalSupply = newKwhTotal;
        celData.totalSupply = newCelTotal;
        
        _mintBatch(to, ids, amounts, "");
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override whenNotPaused {
        super._update(from, to, ids, values);
    }

    // Getter functions for compatibility with tests
    function maxSupply(uint256 tokenId) external view returns (uint256) {
        return supplyData[tokenId].maxSupply;
    }

    function totalSupply(uint256 tokenId) external view returns (uint256) {
        return supplyData[tokenId].totalSupply;
    }
}

/// @title CELToken - Optimized ERC721 Certificate Token
contract CELToken is ERC721URIStorage, AccessControl, Pausable {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 public nextTokenId = 1;
    uint256 public constant MAX_SUPPLY = 1_000_000;

    mapping(uint256 => bool) public isRevoked;
    
    // Reputation system integration
    mapping(address => uint256) public userCertificateCount;

    event CertificateIssued(address indexed to, uint256 indexed tokenId, string metadataCID);
    event CertificateRevoked(uint256 indexed tokenId);
    event BatchCertificatesIssued(address[] indexed recipients, uint256[] tokenIds);

    constructor() ERC721("Clean Energy Certificate", "CEL") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721URIStorage, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function mintCertificate(address to, string memory metadataCID) external onlyRole(ISSUER_ROLE) whenNotPaused returns (uint256) {
        if (to == address(0)) revert InvalidAddress();
        if (bytes(metadataCID).length == 0) revert EmptyMetadata();
        if (nextTokenId > MAX_SUPPLY) revert ExceedsMaxSupply();

        uint256 tokenId = nextTokenId;
        unchecked {
            nextTokenId++;
            userCertificateCount[to]++;
        }
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, metadataCID);
        
        emit CertificateIssued(to, tokenId, metadataCID);
        return tokenId;
    }

    /// @notice Mint multiple certificates in batch
    function mintBatchCertificates(
        address[] calldata recipients,
        string[] calldata metadataCIDs
    ) external onlyRole(ISSUER_ROLE) whenNotPaused returns (uint256[] memory tokenIds) {
        if (recipients.length != metadataCIDs.length) revert ArrayLengthMismatch();
        if (recipients.length > 20) revert BatchSizeLimit();
        if (nextTokenId + recipients.length > MAX_SUPPLY) revert ExceedsMaxSupply();
        
        tokenIds = new uint256[](recipients.length);
        
        for (uint256 i = 0; i < recipients.length;) {
            if (recipients[i] == address(0)) revert InvalidAddress();
            if (bytes(metadataCIDs[i]).length == 0) revert EmptyMetadata();
            
            uint256 tokenId = nextTokenId;
            unchecked {
                nextTokenId++;
                userCertificateCount[recipients[i]]++;
            }
            
            tokenIds[i] = tokenId;
            _safeMint(recipients[i], tokenId);
            _setTokenURI(tokenId, metadataCIDs[i]);
            
            unchecked { ++i; }
        }
        
        emit BatchCertificatesIssued(recipients, tokenIds);
        return tokenIds;
    }

    function revokeCertificate(uint256 tokenId) external onlyRole(ISSUER_ROLE) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        if (isRevoked[tokenId]) revert CertificateAlreadyRevoked();
        
        isRevoked[tokenId] = true;
        emit CertificateRevoked(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenDoesNotExist();
        if (isRevoked[tokenId]) revert CertificateIsRevoked();
        return super.tokenURI(tokenId);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _update(address to, uint256 tokenId, address auth) internal override whenNotPaused returns (address) {
        if (isRevoked[tokenId]) revert CertificateIsRevoked();
        return super._update(to, tokenId, auth);
    }
}

/// @title ContractFactory - Optimized contract deployment registry with CREATE2
contract ContractFactory is AccessControl, ReentrancyGuard {
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");
    
    address[] public deployedContracts;
    mapping(address => bool) public isValidContract;
    mapping(address => uint256) public contractIndex;
    
    // Template addresses for CREATE2 deployment
    address public immutable kwhTokenTemplate;
    address public immutable celTokenTemplate;
    address public immutable paymentTokenTemplate;

    event ContractDeployed(address indexed tradeContract, address indexed deployer, bytes32 salt);
    event ContractRemoved(address indexed tradeContract);

    constructor(
        address _kwhTokenTemplate,
        address _celTokenTemplate,
        address _paymentTokenTemplate
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        kwhTokenTemplate = _kwhTokenTemplate;
        celTokenTemplate = _celTokenTemplate;
        paymentTokenTemplate = _paymentTokenTemplate;
    }

    function register(address newContract) external onlyRole(DEPLOYER_ROLE) nonReentrant {
        if (newContract == address(0)) revert InvalidAddress();
        if (isValidContract[newContract]) revert AlreadyRegistered();
        if (newContract.code.length == 0) revert NotContract();

        deployedContracts.push(newContract);
        isValidContract[newContract] = true;
        contractIndex[newContract] = deployedContracts.length - 1;
        
        emit ContractDeployed(newContract, msg.sender, bytes32(0));
    }

    /// @notice Deploy trade contract using CREATE2 for predictable addresses
    function deployTradeContract(
        address seller,
        address buyer,
        uint256 pricePerKWh,
        uint256 totalKWh,
        uint256 deadline,
        bytes32 salt
    ) external onlyRole(DEPLOYER_ROLE) nonReentrant returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(EnergyTradeContract).creationCode,
            abi.encode(
                seller, buyer, pricePerKWh, totalKWh, deadline,
                kwhTokenTemplate, celTokenTemplate, paymentTokenTemplate
            )
        );
        
        address contractAddr;
        assembly {
            contractAddr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(contractAddr) { revert(0, 0) }
        }
        
        deployedContracts.push(contractAddr);
        isValidContract[contractAddr] = true;
        contractIndex[contractAddr] = deployedContracts.length - 1;
        
        emit ContractDeployed(contractAddr, msg.sender, salt);
        return contractAddr;
    }

    /// @notice Predict the address of a trade contract before deployment
    function predictTradeContractAddress(
        address seller,
        address buyer,
        uint256 pricePerKWh,
        uint256 totalKWh,
        uint256 deadline,
        bytes32 salt
    ) external view returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(EnergyTradeContract).creationCode,
            abi.encode(
                seller, buyer, pricePerKWh, totalKWh, deadline,
                kwhTokenTemplate, celTokenTemplate, paymentTokenTemplate
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(bytecode)
            )
        );
        
        return address(uint160(uint256(hash)));
    }

    function removeContract(address contractAddr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!isValidContract[contractAddr]) revert NotRegistered();
        
        uint256 index = contractIndex[contractAddr];
        uint256 lastIndex = deployedContracts.length - 1;
        
        if (index != lastIndex) {
            address lastContract = deployedContracts[lastIndex];
            deployedContracts[index] = lastContract;
            contractIndex[lastContract] = index;
        }
        
        deployedContracts.pop();
        delete isValidContract[contractAddr];
        delete contractIndex[contractAddr];
        
        emit ContractRemoved(contractAddr);
    }

    function getAllContracts() external view returns (address[] memory) {
        return deployedContracts;
    }

    function getContractCount() external view returns (uint256) {
        return deployedContracts.length;
    }
}

/// @title EnergyTradeContract - Highly optimized energy trading contract with advanced features
contract EnergyTradeContract is AccessControl, ReentrancyGuard, Pausable, EIP712 {

    bytes32 public constant TRADE_ROLE = keccak256("TRADE_ROLE");
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    // EIP-712 type hashes
    bytes32 private constant DELIVERY_TYPEHASH = keccak256(
        "Delivery(uint256 amount,string metadataCID,uint256 nonce,address contract,uint256 deadline)"
    );
    
    bytes32 private constant BATCH_DELIVERY_TYPEHASH = keccak256(
        "BatchDelivery(uint256[] amounts,string[] metadataCIDs,uint256 nonce,address contract,uint256 deadline)"
    );

    // Immutable contract parameters
    address public immutable seller;
    address public immutable buyer;
    uint256 public immutable pricePerKWh;
    uint256 public immutable totalKWh;
    uint256 public immutable deadline;
    uint256 public immutable createdAt;
    uint256 public immutable totalPaymentRequired; // Pre-calculated

    // Gas optimized state variables using bit packing
    struct OptimizedTradeState {
        uint128 deliveredKWh;       // 16 bytes
        uint64 batchCount;          // 8 bytes  
        uint64 flags;               // 8 bytes for multiple boolean flags
        // Total: 32 bytes (1 storage slot)
    }
    
    OptimizedTradeState public tradeState;

    // Flag constants for bit manipulation
    uint64 private constant ACTIVE_FLAG = 1;
    uint64 private constant CANCELLED_FLAG = 2;
    uint64 private constant DISPUTED_FLAG = 4;
    uint64 private constant COMPLETED_FLAG = 8;

    kWhToken public immutable token;
    CELToken public immutable cel;
    IERC20 public immutable paymentToken;

    mapping(address => uint256) public escrowBalances;
    mapping(address => uint256) public nonces;
    
    // Optimized delivery batch storage
    struct DeliveryBatchCore {
        uint96 amount;              // 12 bytes
        uint32 timestamp;           // 4 bytes
        bytes32 metadataHash;       // 32 bytes (separate slot)
    }
    
    mapping(uint256 => DeliveryBatchCore) public deliveryBatches;
    mapping(uint256 => string) public batchMetadata;
    mapping(uint256 => bytes) public batchSignatures;
    mapping(uint256 => string) public deliveryReceipts; // Legacy compatibility

    // Commit-reveal scheme for MEV protection
    mapping(bytes32 => uint256) private commitments;

    // Events
    event EnergyDelivered(address indexed seller, uint256 amount, uint256 indexed batchId);
    event BatchEnergyDelivered(address indexed seller, uint256[] amounts, uint256[] batchIds);
    event TradeCompleted(address indexed buyer, uint256 totalKWh, uint256 indexed certificateId);
    event TradeCancelled(address indexed by, string reason);
    event TradePenalized(address indexed seller, uint256 refundAmount);
    event PaymentDeposited(address indexed buyer, uint256 amount);
    event PaymentWithdrawn(address indexed to, uint256 amount);
    event Refunded(address indexed buyer, uint256 amount);
    event DeliveryReceiptRecorded(uint256 indexed batchId, string metadataCID);
    event DisputeRaised(address indexed by, string reason);
    event DisputeResolved(address indexed resolver, string decision, bool buyerFavored);
    event DeliveryCommitted(address indexed seller, bytes32 commitment);
    event DeadlineWarning(address indexed trade, uint256 timeRemaining);
    event AutomaticPenalty(address indexed seller, uint256 refundAmount);

    modifier onlyTradeParticipants() {
        if (msg.sender != buyer && msg.sender != seller) revert Unauthorized();
        _;
    }

    modifier tradeActive() {
        uint64 flags = tradeState.flags;
        if ((flags & ACTIVE_FLAG) == 0 || (flags & (CANCELLED_FLAG | COMPLETED_FLAG)) != 0) {
            revert TradeNotActive();
        }
        _;
    }

    modifier beforeDeadline() {
        if (block.timestamp > deadline) revert DeadlinePassed();
        _;
    }

    constructor(
        address _seller,
        address _buyer,
        uint256 _pricePerKWh,
        uint256 _totalKWh,
        uint256 _deadline,
        address _kWhToken,
        address _celToken,
        address _paymentToken
    ) EIP712("EnergyTradeContract", "1") {
        if (_seller == address(0) || _buyer == address(0)) revert InvalidAddress();
        if (_seller == _buyer) revert SameAddress();
        if (_pricePerKWh == 0 || _totalKWh == 0) revert InvalidAmount();
        if (_deadline <= block.timestamp) revert InvalidDeadline();
        if (_kWhToken == address(0) || _celToken == address(0) || _paymentToken == address(0)) revert InvalidTokenAddress();

        // Validate token contracts
        if (!IERC165(_kWhToken).supportsInterface(type(IERC20).interfaceId)) revert InvalidTokenAddress();
        if (!IERC165(_celToken).supportsInterface(type(IERC721).interfaceId)) revert InvalidTokenAddress();
        if (!IERC165(_paymentToken).supportsInterface(type(IERC20).interfaceId)) revert InvalidTokenAddress();

        // Calculate total payment and check for overflow
        uint256 _totalPaymentRequired = _totalKWh * _pricePerKWh;
        if (_totalPaymentRequired / _pricePerKWh != _totalKWh) revert NumericOverflow();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ARBITRATOR_ROLE, msg.sender);
        
        seller = _seller;
        buyer = _buyer;
        pricePerKWh = _pricePerKWh;
        totalKWh = _totalKWh;
        deadline = _deadline;
        createdAt = block.timestamp;
        totalPaymentRequired = _totalPaymentRequired;
        token = kWhToken(_kWhToken);
        cel = CELToken(_celToken);
        paymentToken = IERC20(_paymentToken);
        
        tradeState = OptimizedTradeState({
            deliveredKWh: 0,
            batchCount: 0,
            flags: ACTIVE_FLAG
        });
    }

    /// @notice Deposit escrow with batch support
    function depositEscrow(uint256 amount) external nonReentrant whenNotPaused {
        if (msg.sender != buyer) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        
        uint64 flags = tradeState.flags;
        if ((flags & ACTIVE_FLAG) == 0 || (flags & CANCELLED_FLAG) != 0) revert TradeNotActive();
        
        uint256 currentBalance = escrowBalances[buyer];
        
        // Check for overflow
        if (currentBalance > type(uint256).max - amount) revert NumericOverflow();
        if (currentBalance + amount > totalPaymentRequired) revert ExceedsMaxSupply();
        
        if (!paymentToken.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        
        unchecked {
            escrowBalances[buyer] += amount;
        }
        
        emit PaymentDeposited(msg.sender, amount);
    }

    /// @notice Batch deposit escrow to reduce transaction costs
    function depositEscrowBatch(uint256[] calldata amounts) external nonReentrant whenNotPaused {
        if (msg.sender != buyer) revert Unauthorized();
        if (amounts.length > 10) revert BatchSizeLimit();
        
        uint64 flags = tradeState.flags;
        if ((flags & ACTIVE_FLAG) == 0 || (flags & CANCELLED_FLAG) != 0) revert TradeNotActive();
        
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length;) {
            totalAmount += amounts[i];
            unchecked { ++i; }
        }
        
        uint256 currentBalance = escrowBalances[buyer];
        if (currentBalance + totalAmount > totalPaymentRequired) revert ExceedsMaxSupply();
        
        if (!paymentToken.transferFrom(msg.sender, address(this), totalAmount)) revert TransferFailed();
        
        escrowBalances[buyer] += totalAmount;
        emit PaymentDeposited(msg.sender, totalAmount);
    }

    /// @notice Commit to a delivery (MEV protection)
    function commitDelivery(bytes32 commitment) external {
        if (msg.sender != seller) revert Unauthorized();
        commitments[commitment] = block.timestamp;
        emit DeliveryCommitted(msg.sender, commitment);
    }

    /// @notice Reveal and execute delivery with commit-reveal scheme
    function revealDelivery(
        uint256 amount,
        string memory metadataCID,
        uint256 nonce
    ) external nonReentrant tradeActive beforeDeadline {
        bytes32 commitment = keccak256(abi.encodePacked(amount, metadataCID, nonce, msg.sender));
        if (commitments[commitment] == 0) revert InvalidCommitment();
        if (block.timestamp < commitments[commitment] + 1 minutes) revert CommitmentTooEarly();
        
        delete commitments[commitment];
        _deliver(amount, metadataCID, "");
    }

    /// @notice Standard delivery function
    function deliver(uint256 amount, string memory metadataCID) external nonReentrant tradeActive beforeDeadline {
        _deliver(amount, metadataCID, "");
    }

    /// @notice Delivery with EIP-712 signature
    function deliver(uint256 amount, string memory metadataCID, bytes memory signature) external nonReentrant tradeActive beforeDeadline {
        _deliver(amount, metadataCID, signature);
    }

    /// @notice Batch delivery for multiple amounts
    function deliverBatch(
        uint256[] calldata amounts,
        string[] calldata metadataCIDs
    ) external nonReentrant tradeActive beforeDeadline {
        if (msg.sender != seller) revert Unauthorized();
        if (!hasRole(TRADE_ROLE, msg.sender)) revert Unauthorized();
        if (amounts.length != metadataCIDs.length) revert ArrayLengthMismatch();
        if (amounts.length > 10) revert BatchSizeLimit();
        
        uint64 flags = tradeState.flags;
        if ((flags & DISPUTED_FLAG) != 0) revert TradeInDispute();
        
        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length;) {
            totalAmount += amounts[i];
            if (bytes(metadataCIDs[i]).length == 0) revert EmptyMetadata();
            unchecked { ++i; }
        }
        
        // Check overflow and limits
        uint128 currentDelivered = tradeState.deliveredKWh;
        if (currentDelivered > type(uint256).max - totalAmount) revert NumericOverflow();
        if (currentDelivered + totalAmount > totalKWh) revert ExceedsAgreedAmount();

        uint256 totalPaymentDue = totalAmount * pricePerKWh;
        if (escrowBalances[buyer] < totalPaymentDue) revert InsufficientEscrow();

        // Update state before external calls (CEI pattern)
        uint64 newBatchCount = tradeState.batchCount + uint64(amounts.length);
        tradeState.deliveredKWh = uint128(currentDelivered + totalAmount);
        tradeState.batchCount = newBatchCount;
        escrowBalances[buyer] -= totalPaymentDue;
        
        uint256[] memory batchIds = new uint256[](amounts.length);
        
        // Store delivery batches
        for (uint256 i = 0; i < amounts.length;) {
            uint256 batchId = newBatchCount - uint64(amounts.length) + uint64(i) + 1;
            batchIds[i] = batchId;
            
            deliveryBatches[batchId] = DeliveryBatchCore({
                amount: uint96(amounts[i]),
                timestamp: uint32(block.timestamp),
                metadataHash: keccak256(bytes(metadataCIDs[i]))
            });
            
            batchMetadata[batchId] = metadataCIDs[i];
            deliveryReceipts[batchId] = metadataCIDs[i]; // Legacy compatibility
            
            emit DeliveryReceiptRecorded(batchId, metadataCIDs[i]);
            unchecked { ++i; }
        }

        // External calls at the end
        if (!paymentToken.transfer(seller, totalPaymentDue)) revert TransferFailed();
        token.mint(buyer, totalAmount);

        emit BatchEnergyDelivered(seller, amounts, batchIds);
        emit PaymentWithdrawn(seller, totalPaymentDue);

        // Check if trade is completed
        if (tradeState.deliveredKWh == totalKWh) {
            tradeState.flags = (tradeState.flags & ~ACTIVE_FLAG) | COMPLETED_FLAG;
            uint256 certificateId = cel.mintCertificate(buyer, metadataCIDs[metadataCIDs.length - 1]);
            emit TradeCompleted(buyer, totalKWh, certificateId);
        }
    }

    /// @notice Batch delivery with EIP-712 signature verification
    function deliverBatch(
        uint256[] calldata amounts,
        string[] calldata metadataCIDs,
        bytes memory signature
    ) external nonReentrant tradeActive beforeDeadline {
        if (msg.sender != seller) revert Unauthorized();
        if (!hasRole(TRADE_ROLE, msg.sender)) revert Unauthorized();
        
        // Verify EIP-712 signature
        if (signature.length > 0) {
            bytes32 structHash = keccak256(abi.encode(
                BATCH_DELIVERY_TYPEHASH,
                keccak256(abi.encodePacked(amounts)),
                keccak256(abi.encode(metadataCIDs)),
                nonces[buyer],
                address(this),
                deadline
            ));
            
            bytes32 digest = _hashTypedDataV4(structHash);
            address signer = ECDSA.recover(digest, signature);
            if (signer != buyer) revert InvalidSignature();
            
            unchecked {
                nonces[buyer]++;
            }
        }
        
        // Reuse batch delivery logic
        this.deliverBatch(amounts, metadataCIDs);
    }

    /// @notice Internal delivery function with optimizations
    function _deliver(uint256 amount, string memory metadataCID, bytes memory signature) private {
        if (msg.sender != seller) revert Unauthorized();
        if (!hasRole(TRADE_ROLE, msg.sender)) revert Unauthorized();
        
        uint64 flags = tradeState.flags;
        if ((flags & DISPUTED_FLAG) != 0) revert TradeInDispute();
        if (bytes(metadataCID).length == 0) revert EmptyMetadata();
        
        if (amount == 0) return; // Allow zero amount deliveries
        
        // Check overflow and limits
        uint128 currentDelivered = tradeState.deliveredKWh;
        if (currentDelivered > type(uint256).max - amount) revert NumericOverflow();
        if (currentDelivered + amount > totalKWh) revert ExceedsAgreedAmount();

        // Verify EIP-712 signature if provided
        if (signature.length > 0) {
            bytes32 structHash = keccak256(abi.encode(
                DELIVERY_TYPEHASH,
                amount,
                keccak256(bytes(metadataCID)),
                nonces[buyer],
                address(this),
                deadline
            ));
            
            bytes32 digest = _hashTypedDataV4(structHash);
            address signer = ECDSA.recover(digest, signature);
            if (signer != buyer) revert InvalidSignature();
            
            unchecked {
                nonces[buyer]++;
            }
        }

        uint256 paymentDue = amount * pricePerKWh;
        if (escrowBalances[buyer] < paymentDue) revert InsufficientEscrow();

        // Update state before external calls (CEI pattern)
        unchecked {
            tradeState.deliveredKWh = uint128(currentDelivered + amount);
            tradeState.batchCount = tradeState.batchCount + 1;
            escrowBalances[buyer] -= paymentDue;
        }
        
        uint256 newBatchId = tradeState.batchCount;
        
        // Store delivery batch
        deliveryBatches[newBatchId] = DeliveryBatchCore({
            amount: uint96(amount),
            timestamp: uint32(block.timestamp),
            metadataHash: keccak256(bytes(metadataCID))
        });

        batchMetadata[newBatchId] = metadataCID;
        if (signature.length > 0) {
            batchSignatures[newBatchId] = signature;
        }
        
        // Legacy compatibility
        deliveryReceipts[newBatchId] = metadataCID;

        // External calls at the end to prevent reentrancy
        if (!paymentToken.transfer(seller, paymentDue)) revert TransferFailed();
        token.mint(buyer, amount);

        emit DeliveryReceiptRecorded(newBatchId, metadataCID);
        emit PaymentWithdrawn(seller, paymentDue);
        emit EnergyDelivered(seller, amount, newBatchId);

        if (tradeState.deliveredKWh == totalKWh) {
            tradeState.flags = (tradeState.flags & ~ACTIVE_FLAG) | COMPLETED_FLAG;
            uint256 certificateId = cel.mintCertificate(buyer, metadataCID);
            emit TradeCompleted(buyer, totalKWh, certificateId);
        }
    }

    /// @notice Cancel trade with reason
    function cancelTrade() external onlyTradeParticipants nonReentrant {
        _cancelTrade("Trade cancelled by participant");
    }

    function cancelTrade(string memory reason) external onlyTradeParticipants nonReentrant {
        _cancelTrade(reason);
    }

    function _cancelTrade(string memory reason) private {
        uint64 flags = tradeState.flags;
        if ((flags & ACTIVE_FLAG) == 0 || (flags & COMPLETED_FLAG) != 0) revert TradeNotActive();
        if (bytes(reason).length == 0) revert ReasonRequired();
        
        tradeState.flags = (flags & ~ACTIVE_FLAG) | CANCELLED_FLAG;

        uint256 refundAmount = escrowBalances[buyer];
        if (refundAmount > 0) {
            escrowBalances[buyer] = 0;
            if (!paymentToken.transfer(buyer, refundAmount)) revert TransferFailed();
            emit Refunded(buyer, refundAmount);
        }

        emit TradeCancelled(msg.sender, reason);
    }

    /// @notice Penalize seller after deadline
    function penalizeSeller() external nonReentrant {
        if (block.timestamp <= deadline) revert DeadlineNotReached();
        if (tradeState.deliveredKWh >= totalKWh) revert TradeNotActive();
        
        uint64 flags = tradeState.flags;
        if ((flags & (CANCELLED_FLAG | COMPLETED_FLAG)) != 0) revert TradeNotActive();
        
        tradeState.flags = flags & ~ACTIVE_FLAG;

        uint256 refundAmount = escrowBalances[buyer];
        if (refundAmount > 0) {
            escrowBalances[buyer] = 0;
            if (!paymentToken.transfer(buyer, refundAmount)) revert TransferFailed();
            emit Refunded(buyer, refundAmount);
        }

        emit TradePenalized(seller, refundAmount);
        emit AutomaticPenalty(seller, refundAmount);
    }

    /// @notice Automatic penalty processing (can be called by keepers)
    function processAutomaticPenalty() external {
        if (block.timestamp <= deadline) revert DeadlineNotReached();
        
        uint64 flags = tradeState.flags;
        if ((flags & (COMPLETED_FLAG | CANCELLED_FLAG)) != 0) revert TradeNotActive();
        if ((flags & ACTIVE_FLAG) == 0) revert TradeNotActive();
        
        // Call internal penalization logic to avoid external call
        _penalizeSeller();
    }

    /// @notice Internal penalization logic
    function _penalizeSeller() internal {
        uint64 flags = tradeState.flags;
        tradeState.flags = flags & ~ACTIVE_FLAG;

        uint256 refundAmount = escrowBalances[buyer];
        if (refundAmount > 0) {
            escrowBalances[buyer] = 0;
            if (!paymentToken.transfer(buyer, refundAmount)) revert TransferFailed();
            emit Refunded(buyer, refundAmount);
        }

        emit TradePenalized(seller, refundAmount);
        emit AutomaticPenalty(seller, refundAmount);
    }

    /// @notice Check if deadline warning should be issued
    function checkDeadlineStatus() external view returns (bool nearDeadline, bool pastDeadline) {
        uint256 timeLeft = block.timestamp <= deadline ? deadline - block.timestamp : 0;
        nearDeadline = timeLeft <= 24 hours && timeLeft > 0;
        pastDeadline = timeLeft == 0 && (tradeState.flags & COMPLETED_FLAG) == 0;
    }

    /// @notice Emit deadline warning (can be called by monitoring systems)
    function emitDeadlineWarning() external {
        (bool nearDeadline,) = this.checkDeadlineStatus();
        if (nearDeadline) {
            uint256 timeRemaining = deadline - block.timestamp;
            emit DeadlineWarning(address(this), timeRemaining);
        }
    }

    /// @notice Raise dispute with reason
    function raiseDispute(string memory reason) external onlyTradeParticipants {
        uint64 flags = tradeState.flags;
        if ((flags & ACTIVE_FLAG) == 0 || (flags & COMPLETED_FLAG) != 0) revert TradeNotActive();
        if (bytes(reason).length == 0) revert ReasonRequired();
        
        tradeState.flags = flags | DISPUTED_FLAG;
        emit DisputeRaised(msg.sender, reason);
    }

    /// @notice Resolve dispute
    function resolveDispute(string memory decision) external onlyRole(ARBITRATOR_ROLE) nonReentrant {
        _resolveDispute(decision, false);
    }

    function resolveDispute(string memory decision, bool buyerFavored) external onlyRole(ARBITRATOR_ROLE) nonReentrant {
        _resolveDispute(decision, buyerFavored);
    }

    function _resolveDispute(string memory decision, bool buyerFavored) private {
        if ((tradeState.flags & DISPUTED_FLAG) == 0) revert NoActiveDispute();
        if (bytes(decision).length == 0) revert DecisionRequired();
        
        tradeState.flags = tradeState.flags & ~DISPUTED_FLAG;

        if (buyerFavored) {
            uint256 refundAmount = escrowBalances[buyer];
            if (refundAmount > 0) {
                escrowBalances[buyer] = 0;
                if (!paymentToken.transfer(buyer, refundAmount)) revert TransferFailed();
                emit Refunded(buyer, refundAmount);
            }
        }

        emit DisputeResolved(msg.sender, decision, buyerFavored);
    }

    /// @notice Get delivery batch with full metadata
    function getDeliveryBatch(uint256 batchId) external view returns (
        uint256 amount,
        uint256 timestamp,
        string memory metadataCID,
        bytes32 metadataHash,
        bytes memory signature
    ) {
        if (batchId == 0 || batchId > tradeState.batchCount) revert InvalidBatchId();
        
        DeliveryBatchCore memory core = deliveryBatches[batchId];
        return (
            core.amount,
            core.timestamp,
            batchMetadata[batchId],
            core.metadataHash,
            batchSignatures[batchId]
        );
    }

    /// @notice Get comprehensive trade status
    function getTradeStatus() external view returns (
        bool active,
        bool cancelled,
        bool completed,
        bool disputed,
        uint256 delivered,
        uint256 remaining,
        uint256 timeLeft
    ) {
        uint64 flags = tradeState.flags;
        return (
            (flags & ACTIVE_FLAG) != 0,
            (flags & CANCELLED_FLAG) != 0,
            (flags & COMPLETED_FLAG) != 0,
            (flags & DISPUTED_FLAG) != 0,
            tradeState.deliveredKWh,
            totalKWh - tradeState.deliveredKWh,
            block.timestamp <= deadline ? deadline - block.timestamp : 0
        );
    }

    /// @notice Get trade progress as percentage (0-10000 for 0-100.00%)
    function getTradeProgress() external view returns (uint256 progressBasisPoints) {
        if (totalKWh == 0) return 0;
        return (tradeState.deliveredKWh * 10000) / totalKWh;
    }

    /// @notice Get escrow utilization percentage
    function getEscrowUtilization() external view returns (uint256 utilizationBasisPoints) {
        if (totalPaymentRequired == 0) return 0;
        return (escrowBalances[buyer] * 10000) / totalPaymentRequired;
    }

    /// @notice Get batch delivery summary
    function getBatchSummary() external view returns (
        uint256 totalBatches,
        uint256 averageBatchSize,
        uint256 lastDeliveryTime
    ) {
        uint64 batchCount = tradeState.batchCount;
        totalBatches = batchCount;
        
        if (batchCount > 0) {
            averageBatchSize = tradeState.deliveredKWh / batchCount;
            lastDeliveryTime = deliveryBatches[batchCount].timestamp;
        }
    }

    function getNonce(address account) external view returns (uint256) {
        return nonces[account];
    }

    /// @notice Get the total amount of kWh delivered so far
    function deliveredKWh() external view returns (uint256) {
        return tradeState.deliveredKWh;
    }

    /// @notice Get the total amount of kWh delivered so far (alternative naming)
    function getDeliveredKWh() external view returns (uint256) {
        return tradeState.deliveredKWh;
    }

    /// @notice Check if the trade is active
    function isActive() external view returns (bool) {
        uint64 flags = tradeState.flags;
        return (flags & ACTIVE_FLAG) != 0 && (flags & (CANCELLED_FLAG | COMPLETED_FLAG)) == 0;
    }

    /// @notice Check if the trade is disputed
    function isDisputed() external view returns (bool) {
        return (tradeState.flags & DISPUTED_FLAG) != 0;
    }

    /// @notice Check if trade is completed
    function isCompleted() external view returns (bool) {
        return (tradeState.flags & COMPLETED_FLAG) != 0;
    }

    /// @notice Check if trade is cancelled
    function isCancelled() external view returns (bool) {
        return (tradeState.flags & CANCELLED_FLAG) != 0;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Emergency function to rescue tokens (only admin)
    function emergencyWithdraw(address tokenAddress, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tokenAddress == address(paymentToken)) revert InvalidTokenAddress();
        if (!IERC20(tokenAddress).transfer(msg.sender, amount)) revert TransferFailed();
    }

    /// @notice Get domain separator for EIP-712
    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Verify delivery signature without executing
    function verifyDeliverySignature(
        uint256 amount,
        string memory metadataCID,
        uint256 nonce,
        uint256 signatureDeadline,
        bytes memory signature
    ) external view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(
            DELIVERY_TYPEHASH,
            amount,
            keccak256(bytes(metadataCID)),
            nonce,
            address(this),
            signatureDeadline
        ));
        
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);
        return signer == buyer;
    }

    /// @notice Get commitment for delivery (helper for commit-reveal)
    function getDeliveryCommitment(
        uint256 amount,
        string memory metadataCID,
        uint256 nonce,
        address sender
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(amount, metadataCID, nonce, sender));
    }
}

/// @title ReputationSystem - Track user performance and reliability
contract ReputationSystem is AccessControl {
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    
    struct UserReputation {
        uint64 completedTrades;
        uint64 totalTrades;
        uint64 averageDeliveryTime; // in hours
        uint64 disputesLost;
        uint64 onTimeDeliveries;
        uint64 lastUpdated;
    }
    
    mapping(address => UserReputation) public reputations;
    
    event ReputationUpdated(
        address indexed user,
        uint64 completedTrades,
        uint64 totalTrades,
        uint64 disputesLost
    );
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    function updateReputation(
        address user,
        bool tradeCompleted,
        bool onTime,
        bool disputeLost,
        uint256 deliveryTimeHours
    ) external onlyRole(UPDATER_ROLE) {
        UserReputation storage rep = reputations[user];
        
        rep.totalTrades++;
        if (tradeCompleted) {
            rep.completedTrades++;
            if (onTime) rep.onTimeDeliveries++;
        }
        if (disputeLost) rep.disputesLost++;
        
        // Update average delivery time (weighted average)
        if (deliveryTimeHours > 0) {
            rep.averageDeliveryTime = uint64(
                (rep.averageDeliveryTime * (rep.completedTrades - 1) + deliveryTimeHours) / rep.completedTrades
            );
        }
        
        rep.lastUpdated = uint64(block.timestamp);
        
        emit ReputationUpdated(user, rep.completedTrades, rep.totalTrades, rep.disputesLost);
    }
    
    function getReputationScore(address user) external view returns (uint256 score) {
        UserReputation memory rep = reputations[user];
        
        if (rep.totalTrades == 0) return 0;
        
        // Calculate score (0-1000)
        uint256 completionRate = (rep.completedTrades * 1000) / rep.totalTrades;
        uint256 onTimeRate = rep.completedTrades > 0 ? (rep.onTimeDeliveries * 1000) / rep.completedTrades : 0;
        uint256 disputeRate = rep.totalTrades > 0 ? (rep.disputesLost * 1000) / rep.totalTrades : 0;
        
        // Weighted score: 40% completion, 40% on-time, 20% dispute penalty
        score = (completionRate * 40 + onTimeRate * 40) / 100;
        if (score > disputeRate * 20 / 100) {
            score -= disputeRate * 20 / 100;
        } else {
            score = 0;
        }
        
        return score;
    }
}

/// @title EnergyTradeFactory - Advanced factory with CREATE2 and templates
contract EnergyTradeFactory is ContractFactory {
    ReputationSystem public immutable reputationSystem;
    
    // Trade templates for different energy types
    mapping(string => address) public tradeTemplates;
    
    event TradeTemplateAdded(string indexed energyType, address template);
    event TradeCreatedFromTemplate(
        address indexed tradeContract,
        string indexed energyType,
        address indexed creator
    );
    
    constructor(
        address _kwhTokenTemplate,
        address _celTokenTemplate,
        address _paymentTokenTemplate,
        address _reputationSystem
    ) ContractFactory(_kwhTokenTemplate, _celTokenTemplate, _paymentTokenTemplate) {
        reputationSystem = ReputationSystem(_reputationSystem);
        _grantRole(DEPLOYER_ROLE, msg.sender);
    }
    
    function addTradeTemplate(string memory energyType, address template) external onlyRole(DEFAULT_ADMIN_ROLE) {
        tradeTemplates[energyType] = template;
        emit TradeTemplateAdded(energyType, template);
    }
    
    function createTradeFromTemplate(
        string memory energyType,
        address seller,
        address buyer,
        uint256 pricePerKWh,
        uint256 totalKWh,
        uint256 deadline,
        bytes32 salt
    ) external onlyRole(DEPLOYER_ROLE) returns (address) {
        address template = tradeTemplates[energyType];
        if (template == address(0)) revert NotRegistered();
        
        address tradeContract = this.deployTradeContract(
            seller, buyer, pricePerKWh, totalKWh, deadline, salt
        );
        
        emit TradeCreatedFromTemplate(tradeContract, energyType, msg.sender);
        return tradeContract;
    }
}