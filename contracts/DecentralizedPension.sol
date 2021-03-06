pragma solidity ^0.4.0;

import "./DecentralizedPensionToken.sol";
import "./DateTime.sol";

contract DecentralizedPension {
    DateTime dateTime;
    DecentralizedPensionToken public pensionToken;

    event Debug(uint256 data);
    event Deposit(address indexed sender, uint256 amount);
    event Claim(address indexed sender, uint256 amount);
    event Withdraw(address indexed sender, uint256 myActivatedPart, uint256 distributionPercentage, uint256 distributionAmount, uint256 amount);
    event Retire(address indexed sender, uint256 amount, uint256 monthFactor, uint256 totalMonthFactor);

    uint public creationTimestamp;

    mapping(address => bool) public isRetired;

    mapping(address => mapping(uint16 => mapping(uint8 => uint256))) public depositsByUser;
    mapping(uint16 => mapping(uint8 => uint256)) public totalDepositsAmountByMonth;
    mapping(uint16 => mapping(uint8 => uint256)) public totalDepositsByMonth;
    mapping(uint16 => mapping(uint8 => uint256)) public minDepositByMonth;
    mapping(uint16 => mapping(uint8 => uint256)) public maxDepositByMonth;
    mapping(uint16 => mapping(uint8 => bool)) public hasWithdrawed;

    mapping(address => uint256) public monthPaidCount;
    mapping(address => uint256) public monthFactors;
    uint256 public totalMonthFactor;

    //uint256 public globalFond;

    constructor(address _dateTime) public {
        creationTimestamp = now;
        dateTime = DateTime(_dateTime);
        pensionToken = new DecentralizedPensionToken();
    }

    /*
     * @dev Deposit eth for for the current month
     */
    function deposit(uint256 _amount) public payable returns (bool) {
        require(_amount == msg.value, "amount must equal msg.value");
        require(_amount > 0, "amount must be greater 0");
        require(!isRetired[msg.sender], "msg.sender must not be retired");

        uint16 _year = dateTime.getYear(now);
        uint8 _month = dateTime.getMonth(now);

        totalDepositsByMonth[_year][_month] += 1;
        totalDepositsAmountByMonth[_year][_month] += _amount;

        if (depositsByUser[msg.sender][_year][_month] == 0) {
            monthPaidCount[msg.sender] += 1;
        }

        depositsByUser[msg.sender][_year][_month] += _amount;

        if (_amount > maxDepositByMonth[_year][_month]) {
            maxDepositByMonth[_year][_month] = _amount;
        }
        if (_amount < minDepositByMonth[_year][_month]) {
            minDepositByMonth[_year][_month] = _amount;
        }

        emit Deposit(msg.sender, _amount);

        return true;
    }

    /*
     * @dev Call with period to claim all pension tokens for that period
     */
    function claim(uint16 _year, uint8 _month) public returns (bool) {
        require(!isRetired[msg.sender], "msg.sender must not be retired");

        uint256 _amount = depositsByUser[msg.sender][_year][_month];
        uint256 _minAmount = minDepositByMonth[_year][_month];
        uint256 _maxAmount = maxDepositByMonth[_year][_month];

        uint256 _targetPrice = targetPrice(_year, _month);

        uint256 _tokenAmount;
        if (_amount >= _targetPrice) {
            _tokenAmount = (1 + ((_amount - _targetPrice + 10 ** 18) / (_maxAmount - _targetPrice + 10 ** 18))) * bonusFactor();
        } else {
            _tokenAmount = ((_amount - _minAmount) / (_targetPrice - _minAmount)) * bonusFactor();
        }

        pensionToken.mint(msg.sender, _tokenAmount * 10 ** 15);
        emit Claim(msg.sender, _tokenAmount * 10 ** 15);

        return true;
    }

    /*
     * @dev Call with amount of DPT to start the pension retiretime
     */
    function retire(uint256 _amount) public returns (bool)  {
        require(!isRetired[msg.sender], "msg.sender must not be retired");

        isRetired[msg.sender] = true;

        pensionToken.burnFrom(msg.sender, _amount);

        monthFactors[msg.sender] = _amount / monthPaidCount[msg.sender];
        totalMonthFactor += monthFactors[msg.sender];

        emit Retire(msg.sender, _amount, monthFactors[msg.sender], totalMonthFactor);

        return true;
    }
    /*
    * @dev payout the  pension
    */
    function withdraw(uint16 _year, uint8 _month) public returns (bool) {
        require(isRetired[msg.sender], "msg.sender must be retired");
        require(!hasWithdrawed[_year][_month], "withdrawal only allowed once");

        hasWithdrawed[_year][_month] = true;

        uint256 myActivatedPart = monthFactors[msg.sender] / totalMonthFactor;

        uint256 distributionPercentage;
        if (pensionToken.totalSupply() > 0) {
            distributionPercentage = totalMonthFactor / pensionToken.totalSupply();
        }

        //this.value

        uint256 distributionAmount = (address(this).balance * distributionPercentage) + totalDepositsAmountByMonth[_year][_month] * (1 - distributionPercentage);

        uint256 pensionPayout = distributionAmount * myActivatedPart;

        msg.sender.transfer(pensionPayout);
        emit Withdraw(msg.sender, myActivatedPart, distributionPercentage, distributionAmount, pensionPayout);
        emit Debug(address(this).balance);

        return true;
    }

    function bonusFactor() internal view returns (uint256) {
        uint256 _yearsRunning = 1 + dateTime.getYear(now) - dateTime.getYear(creationTimestamp);

        uint256 _bonusFactor = 1500 - (15 * _yearsRunning);
        if (_bonusFactor < 1000) {
            _bonusFactor = 1000;
        }

        return _bonusFactor;
    }

    /*
     * TODO: use median instead of average. But we need a sorted array first
     */
    function targetPrice(uint16 _year, uint8 _month) internal view returns (uint256) {
        return totalDepositsAmountByMonth[_year][_month] / totalDepositsByMonth[_year][_month];
    }

    function getMonthPaidCount() public view returns (uint256){
        return monthPaidCount[msg.sender];
    }

    function getMonthFactors() public view returns (uint256){
        return monthFactors[msg.sender];
    }

    function IsRetired() public view returns (bool){
        return isRetired[msg.sender];
    }
}
