// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import './libraries/Ownable.sol';
import './interfaces/IERC20.sol';
import './libraries/SafeMath.sol';
import './interfaces/IOortswapRouter.sol';

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IUniswapV2Factory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

    function pairFor(address tokenA, address tokenB) external view returns (address pair);
}

interface IProvider {
    function getMarginPoolStaking() external view  returns (address);
    function getMarginPool() external view returns (address);
    function getPriceOracle() external view returns (address);
}

interface Token {
    function mint(address _addr,uint256 _amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract SwapMining is Ownable {
    using SafeMath for uint256;

    // oort tokens created per block
    uint256 public oortPerBlock;
    // The block number when oort mining starts.
    uint256 public startBlock;
    // How many blocks are halved
    uint256 public halvingPeriod = 5760000;
    uint256 public extraReward = 1750000;
    // Total allocation points
    uint256 public totalAllocPoint = 0;
    // IOracle public oracle;
    // router address
    address public router;
    // factory address
    IUniswapV2Factory public factory;
    // oort token address
    Token public oort;

    // pair corresponding pid
    mapping(address => uint256) public pairOfPid;
    
    mapping(uint256=>mapping(address=>uint256)) public withdrawAmounts;

    address public staking;
    
    
    event Swap(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        Token _oort,
        address _router,
        uint256 _oortPerBlock,
        uint256 _startBlock,
        address _staking
    ) public {
        oort = _oort;
        factory = IUniswapV2Factory(IOortswapRouter(_router).factory());
        router = _router;
        oortPerBlock = _oortPerBlock;
        startBlock = _startBlock;
        staking = _staking;
    }

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 unclaimedBuni;
    }

    // Info of each pool.
    struct PoolInfo {
        address pair;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that CAKEs distribution occurs.
        uint256 accCakePerShare; // Accumulated CAKEs per share, times 1e12. See below.
        uint256 amount;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function addPair(uint256 _allocPoint, address _pair, bool _withUpdate) public onlyOwner {
        require(_pair != address(0), "_pair is the zero address");
        if (_withUpdate) {
            massMintPools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(PoolInfo({
            pair: _pair,
            allocPoint : _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accCakePerShare: 0,
            amount : 0
        }));

        pairOfPid[_pair] = poolLength() - 1;
    }

    // Update the allocPoint of the pool
    function setPair(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massMintPools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Set the number of oort produced by each block
    function setoortPerBlock(uint256 _newPerBlock) public onlyOwner {
        massMintPools();
        oortPerBlock = _newPerBlock;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }

    function setRouter(address newRouter) public onlyOwner {
        require(newRouter != address(0), "SwapMining: new router is the zero address");
        router = newRouter;
    }

    // At what phase
    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock).sub(1)).div(halvingPeriod);
        }
        return 0;
    }

    function phase() public view returns (uint256) {
        return phase(block.number);
    }

    function reward(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        return oortPerBlock.div(2 ** _phase);
    }

    function reward() public view returns (uint256) {
        return reward(block.number);
    }

    // Rewards for the current block
    function getExtraReward(uint256 _from, uint256 _to,uint256 _lastRewardBlock) internal view returns (uint256) {
        require(_to >= _lastRewardBlock, "SwapMining: extra must little than the current block number");
        
        if(_from.add(extraReward) >= _to) {
            return _to.sub(_lastRewardBlock).mul(3 * 1e18);
        }

        return 0;
    }

   function getOortReward(uint256 _lastRewardBlock) public view returns (uint256) {
        require(_lastRewardBlock <= block.number, "SwapMining: must little than the current block number");
        uint256 blockReward = 0;
        uint256 n = phase(_lastRewardBlock);
        uint256 m = phase(block.number);
        // If it crosses the cycle
        uint256 extraRewards = getExtraReward(startBlock,block.number,_lastRewardBlock);
        while (n < m) {
            n++;
            // Get the last block of the previous cycle
            uint256 r = n.mul(halvingPeriod).add(startBlock);
            // Get rewards from previous periods
            blockReward = blockReward.add((r.sub(_lastRewardBlock)).mul(reward(r)));
            _lastRewardBlock = r;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(reward(block.number)));
        
        return blockReward.add(extraRewards);
    }

    // Update all pools Called when updating allocPoint and setting new blocks
    function massMintPools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function swap(address account, address input, address output, uint256 amount) public onlyRouter returns (bool) {
        require(account != address(0), "SwapMining: taker swap account is the zero address");
        require(input != address(0), "SwapMining: taker swap input is the zero address");
        require(output != address(0), "SwapMining: taker swap output is the zero address");

        if (poolLength() <= 0) {
            return false;
        }

        address pair = factory.getPair(input, output);
        if(pair ==address(0x00)) {
            return false;
        }

        PoolInfo storage pool = poolInfo[pairOfPid[pair]];
        // If it does not exist or the allocPoint is 0 then return
        if (pool.pair != pair || pool.allocPoint <= 0) {
            return false;
        }

        uint256 _pid = pairOfPid[pair];
        UserInfo storage user = userInfo[_pid][account];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCakePerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                user.unclaimedBuni = user.unclaimedBuni.add(pending);
            }
        }

        if(amount > 0){
            user.amount = user.amount.add(amount);
            pool.amount = pool.amount.add(amount);
            
            emit Swap(account, _pid, amount);
        }

        user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);
        
        return true;
    }

    // The user withdraws all the transaction rewards of the pool
    function takerWithdraw(address _addr) public onlyStaking {
        uint256 userSub;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][_addr];
            updatePool(pid);

            if (user.amount > 0) {
                uint256 pending = user.amount.mul(pool.accCakePerShare).div(1e12).sub(user.rewardDebt);
                uint256 userReward = pending.add(user.unclaimedBuni);

                user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);

                if(userReward > 0) {
                    user.unclaimedBuni = 0;
                    pool.amount = pool.amount.sub(user.amount);
                    user.amount = 0;
                    
                    userSub = userSub.add(userReward);
                    
                    withdrawAmounts[pid][_addr] = withdrawAmounts[pid][_addr].add(userReward);
                }
            }

            user.rewardDebt = user.amount.mul(pool.accCakePerShare).div(1e12);
        }

        if (userSub <= 0) {
            return;
        }
        
        safeCakeTransfer(_addr, userSub);
    }
    
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 reserveSupply = pool.amount;   // 本池子占有的LP数量
        if (reserveSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockReward = getOortReward(pool.lastRewardBlock);
        uint256 sushiReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);   // 计算本池子可获得的新的sushi激励
        oort.mint(address(this), sushiReward);     // 将挖出的sushi给此合约
        pool.accCakePerShare = pool.accCakePerShare.add(sushiReward.mul(1e12).div(reserveSupply));  // 计算每个lp可分到的sushi数量
        pool.lastRewardBlock = block.number;        // 记录最新的计算过的区块高度
    }

    function getUserReward(uint256 _pid, address _user) external view returns (uint256,uint256) {
        require(_pid <= poolInfo.length - 1, "marginMining: Not find this pool");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCakePerShare = pool.accCakePerShare;
        uint256 reserveSupply = pool.amount;
        if (block.number > pool.lastRewardBlock && reserveSupply != 0) {
            uint256 blockReward = getOortReward(pool.lastRewardBlock);
            uint256 cakeReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
            accCakePerShare = accCakePerShare.add(cakeReward.mul(1e12).div(reserveSupply));
        }
        
        uint256 userReward = user.amount.mul(accCakePerShare).div(1e12).sub(user.rewardDebt).add(user.unclaimedBuni);

        return (userReward,userReward.add(withdrawAmounts[_pid][_user]));
    }

    modifier onlyRouter() {
        require(msg.sender == router, "SwapMining: caller is not the router");
        _;
    }

    modifier onlyStaking {
        require(_msgSender() == staking, "onlyStaking getMarginPoolStaking");
        _;
   }

   function safeCakeTransfer(address _to, uint256 _amount) internal {
        uint256 oortBal = oort.balanceOf(address(this));
        if (_amount > oortBal) {
            oort.transfer(_to, oortBal);
        } else {
            oort.transfer(_to, _amount);
        }
    }

}
