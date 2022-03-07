// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./OortToken.sol";

interface IMigratorChef {
    function migrate(IERC20 token) external returns (IERC20);
}

contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. OORTs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that OORTs distribution occurs.
        uint256 accOortPerShare; // Accumulated OORTs per share, times 1e12. See below.
    }

    // The OORT TOKEN!
    OortToken public oort;

    // OORT tokens created per block.
    uint256 public oortPerBlock;
    // Bonus muliplier for early oort makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // The migrator contract. It has a lot of power. Can only be set through governance (owner).
    IMigratorChef public migrator;

    uint256 public halvingPeriod = 5760000;
    uint256 public extraReward = 1750000;
                     
    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when OORT mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        OortToken _oort,
        uint256 _oortPerBlock,
        uint256 _startBlock
    )  {
        oort = _oort;
        oortPerBlock = _oortPerBlock;
        startBlock = _startBlock;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
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
        if(_phase > 2) {
            _phase = 2;
        }

        return oortPerBlock.div(2 ** _phase);
    }

    function reward() public view returns (uint256) {
        return reward(block.number);
    }

    function getExtraReward(uint256 _from, uint256 _to,uint256 _lastRewardBlock) internal view returns (uint256) {
        require(_to >= _lastRewardBlock, "SwapMining: extra must little than the current block number");
        
        if(_from.add(extraReward) >= _to) {
            return _to.sub(_lastRewardBlock).mul(6 * 1e18);
        }

        return 0;
    }

    // Rewards for the current block
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

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, address _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accOortPerShare: 0
        }));
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);

    }

    // Set the migrator contract. Can only be called by the owner.
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    // Migrate lp token to another lp contract. Can be called by anyone. We trust that migrator contract is good.
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IERC20 lpToken = IERC20(pool.lpToken);
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IERC20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = address(newLpToken);
    }

    // View function to see pending OORTs on frontend.
    function pendingOort(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accOortPerShare = pool.accOortPerShare;
        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blockReward = getOortReward(pool.lastRewardBlock);
            uint256 oortReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
            accOortPerShare = accOortPerShare.add(oortReward.mul(1e12).div(lpSupply));
        }

        return user.amount.mul(accOortPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {

        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = IERC20(pool.lpToken).balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 blockReward = getOortReward(pool.lastRewardBlock);
        uint256 oortReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
        oort.ChefMint( oortReward); 
        pool.accOortPerShare = pool.accOortPerShare.add(oortReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for OORT allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accOortPerShare).div(1e12).sub(user.rewardDebt);
            safeOortTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
           IERC20(pool.lpToken).safeTransferFrom(address(msg.sender), address(this), _amount);
           user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accOortPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accOortPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeOortTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            IERC20(pool.lpToken).safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount.mul(pool.accOortPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        IERC20(pool.lpToken).safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe oort transfer function, just in case if rounding error causes pool to not have enough OORTs.
   function safeOortTransfer(address _to, uint256 _amount) internal {
        uint256 oortBal = oort.balanceOf(address(this));
        if (_amount > oortBal) {
            oort.transfer(_to, oortBal);
        } else {
            oort.transfer(_to, _amount);
        }
    }
}