
(async function () {
  // Get available accounts
  const accounts = await web3.eth.getAccounts();
  console.log("Accounts:", accounts);

  // Deploy the dummy mintable token first.
  // Make sure the DummyMintableToken artifact is available in Remix.
  const dummyTokenInstance = await DummyMintableToken.new("Dummy Token", "DMT", { from: accounts[0] });
  console.log("DummyMintableToken deployed at:", dummyTokenInstance.address);

  // Deploy the HFRebtateToken contract, passing the dummy token address and an initial fee discount.
  const initialFeeDiscount = 5;
  const hfInstance = await HFRebtateToken.new(dummyTokenInstance.address, initialFeeDiscount, { from: accounts[0] });
  console.log("HFRebtateToken deployed at:", hfInstance.address);

  // Initialize governance (using owner account)
  const rebateRate = 10;      // example: 10 (i.e. 1% rebate)
  const maxFeeDiscount = 15;    // example maximum fee discount
  await hfInstance.initializeGovernance(rebateRate, maxFeeDiscount, { from: accounts[0] });
  console.log("Governance initialized.");

  // Have account[1] record a trade
  const tradeAmount = 5000;
  await hfInstance.recordTrade(tradeAmount, { from: accounts[1] });
  const traderInfo = await hfInstance.traders(accounts[1]);
  console.log("Trader info after trade:", traderInfo);

  // Claim rebate for account[1]
  await hfInstance.claimRebate({ from: accounts[1] });
  console.log("Rebate claimed by account:", accounts[1]);

  // (Optionally) log dummy token balance of account[1] after rebate
  const balanceAfter = await dummyTokenInstance.balanceOf(accounts[1]);
  console.log("Dummy token balance of account[1] after rebate:", balanceAfter.toString());

  console.log("Test completed.");
})();
