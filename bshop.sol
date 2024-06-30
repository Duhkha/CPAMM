// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Bshop is ERC20, ReentrancyGuard {
    IERC20 public immutable token;
    uint public reserveToken;
    uint public reserveETH;
    uint public constant MINIMUM_LIQUIDITY = 1000;
    uint32 private blockTimestampLast;
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public constant FEE_DENOMINATOR = 10000;
    uint public feeBasisPoints = 30; // 0.3% fee

    event LiquidityAdded(address indexed provider, uint amountToken, uint amountETH);
    event LiquidityRemoved(address indexed provider, uint amountToken, uint amountETH);
    event Swap(address indexed trader, uint amountIn, uint amountOut, bool ethToToken);

    constructor(address _token) ERC20("Bshop Token", "bshop-LP") {
        token = IERC20(_token);
    }

   function addLiquidity(uint amountToken) external payable nonReentrant returns (uint liquidity) {
    require(amountToken > 0 && msg.value > 0, "Invalid amounts: Token or ETH amount must be greater than 0");

    uint _reserveToken = reserveToken;
    uint _reserveETH = reserveETH;
    uint balanceToken = token.balanceOf(address(this));
    uint balanceETH = address(this).balance - msg.value;
    uint amountETH = msg.value;

    if (_reserveToken == 0 && _reserveETH == 0) {
        // For research purposes, we skip locking the minimum liquidity
        liquidity = Math.sqrt(amountToken * amountETH);
    } else {
        uint liquidityToken = (amountToken * totalSupply()) / _reserveToken;
        uint liquidityETH = (amountETH * totalSupply()) / _reserveETH;
        liquidity = Math.min(liquidityToken, liquidityETH);
    }

    require(liquidity > 0, "Insufficient liquidity minted");

    _mint(msg.sender, liquidity);
    _update(balanceToken + amountToken, balanceETH + amountETH);
    token.transferFrom(msg.sender, address(this), amountToken);
    emit LiquidityAdded(msg.sender, amountToken, amountETH);
}


    function removeLiquidity(uint liquidity) external nonReentrant returns (uint amountToken, uint amountETH) {
        require(liquidity > 0, "Invalid liquidity amount");
        uint balanceToken = token.balanceOf(address(this));
        uint balanceETH = address(this).balance;

        amountToken = (liquidity * balanceToken) / totalSupply();
        amountETH = (liquidity * balanceETH) / totalSupply();
        require(amountToken > 0 && amountETH > 0, "Insufficient liquidity burned");

        _burn(msg.sender, liquidity);
        _update(balanceToken - amountToken, balanceETH - amountETH);

        token.transfer(msg.sender, amountToken);
        payable(msg.sender).transfer(amountETH);

        emit LiquidityRemoved(msg.sender, amountToken, amountETH);
    }

    function swapETHForToken(uint minAmountOut) external payable nonReentrant returns (uint amountOut) {
        require(msg.value > 0, "Invalid ETH amount");
        uint balanceToken = token.balanceOf(address(this));
        uint balanceETH = address(this).balance - msg.value;

        amountOut = getAmountOut(msg.value, balanceETH, balanceToken);
        require(amountOut >= minAmountOut, "Insufficient output amount");

        token.transfer(msg.sender, amountOut);
        _update(balanceToken - amountOut, balanceETH + msg.value);

        emit Swap(msg.sender, msg.value, amountOut, true);
    }

    function swapTokenForETH(uint amountIn, uint minAmountOut) external nonReentrant returns (uint amountOut) {
        require(amountIn > 0, "Invalid token amount");
        uint balanceToken = token.balanceOf(address(this));
        uint balanceETH = address(this).balance;

        amountOut = getAmountOut(amountIn, balanceToken, balanceETH);
        require(amountOut >= minAmountOut, "Insufficient output amount");

        token.transferFrom(msg.sender, address(this), amountIn);
        payable(msg.sender).transfer(amountOut);
        _update(balanceToken + amountIn, balanceETH - amountOut);

        emit Swap(msg.sender, amountIn, amountOut, false);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public view returns (uint amountOut) {
        require(amountIn > 0, "Invalid input amount");
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        uint amountInWithFee = amountIn * (FEE_DENOMINATOR - feeBasisPoints);
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _update(uint balance0, uint balance1) private {
    reserveToken = balance0; 
    reserveETH = balance1;   
    uint32 blockTimestamp = uint32(block.timestamp % 2**32);
    uint32 timeElapsed = blockTimestamp - blockTimestampLast;

    if (timeElapsed > 0 && reserveToken != 0 && reserveETH != 0) {
        price0CumulativeLast += uint(UQ112x112.uqdiv(UQ112x112.encode(uint112(reserveETH)), uint112(reserveToken))) * timeElapsed;

        price1CumulativeLast += uint(UQ112x112.uqdiv(UQ112x112.encode(uint112(reserveToken)), uint112(reserveETH))) * timeElapsed;
    }

    blockTimestampLast = blockTimestamp;
}


    function setFee(uint newFeeBasisPoints) external {
        // Add access control here
        require(newFeeBasisPoints <= 100, "Fee too high"); // Max 1%
        feeBasisPoints = newFeeBasisPoints;
    }

    function checkInvariant() public view returns (bool) {
        uint k = reserveToken * reserveETH;
        uint tolerance = k / 1000; // 0.1% tolerance
        uint balanceToken = token.balanceOf(address(this));
        uint balanceETH = address(this).balance;
        uint currentK = balanceToken * balanceETH;
        return (currentK >= k - tolerance && currentK <= k + tolerance);
    }
}

library UQ112x112 {
    uint224 constant Q112 = 2**112;

    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112;
    }

    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

library Math {
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}