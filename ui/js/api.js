(function () {
  'use strict';

  // ── Network config ───────────────────────────────────────────────────────────
  // Anvil-only. Addresses are deterministic — produced by DeployAnvil.s.sol
  // with account #0 (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266) at nonce 0.
  // Fresh `anvil` instance + `forge script script/DeployAnvil.s.sol --broadcast`
  // always produces these addresses.
  const NETWORK = {
    chainId:  31337,
    rpcUrl:   'http://127.0.0.1:8545',
    baseUnit: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
    subUnit:  '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  };

  // ── ABIs — only functions called by this layer ───────────────────────────────

  const BASE_UNIT_ABI = [
    'function MAX_SUPPLY() view returns (uint256)',
    'function MAX_UNITS_PER_WALLET() view returns (uint256)',
    'function BASE_UNIT_PRICE() view returns (uint256)',
    'function totalSupply() view returns (uint256)',
    'function balanceOf(address) view returns (uint256)',
    'function tokenOfOwnerByIndex(address, uint256) view returns (uint256)',
    'function typeOf(uint256) view returns (uint8)',
    'function subUnitLimitOf(uint256) view returns (uint256)',
    'function getTba(uint256) view returns (address)',
    'function mintBaseUnit() payable returns (uint256)',
    'event BaseUnitMinted(uint256 indexed tokenId, address indexed owner, address tba, uint8 indexed unitType)',
  ];

  const SUB_UNIT_ABI = [
    'function SUB_UNIT_PRICE() view returns (uint256)',
    'function totalCompleted() view returns (uint256)',
    'function totalSubUnitsMinted() view returns (uint256)',
    'function subUnitCountPerBase(uint256) view returns (uint256)',
    'function subUnitScore(uint256) view returns (uint256)',
    'function localScore(uint256) view returns (uint256)',
    'function globalScore(address) view returns (uint256)',
    'function isCompleted(uint256) view returns (bool)',
    'function getSubUnitsForBase(uint256) view returns (uint256[])',
    'function mintSubUnit(uint256) payable returns (uint256)',
    'event SubUnitMinted(uint256 indexed subUnitId, uint256 indexed baseUnitId, address indexed tba, uint256 score)',
  ];

  const TYPE_NAMES = { 0: 'A UNIT', 1: 'B UNIT', 2: 'C UNIT' };

  // ── Mutable — set by initNetwork() ──────────────────────────────────────────
  let _ro       = null;
  let _baseUnit = null;
  let _subUnit  = null;

  // ── Write contracts — set by connectWallet() ─────────────────────────────────
  let _baseUnitW = null;
  let _subUnitW  = null;

  async function _tryProvider(rpcUrl) {
    const p = new ethers.JsonRpcProvider(rpcUrl);
    try {
      await p.getBlockNumber();
      return p;
    } catch (err) {
      p.destroy();
      throw err;
    }
  }

  // ── Network init ─────────────────────────────────────────────────────────────
  // chainId param accepted for API compatibility with main.js — ignored here.
  async function initNetwork(_chainId) {
    _ro       = await _tryProvider(NETWORK.rpcUrl);
    _baseUnit = new ethers.Contract(NETWORK.baseUnit, BASE_UNIT_ABI, _ro);
    _subUnit  = new ethers.Contract(NETWORK.subUnit,  SUB_UNIT_ABI,  _ro);
    return NETWORK.chainId;
  }

  // ── API implementation ────────────────────────────────────────────────────────

  async function connectWallet() {
    if (!window.ethereum) throw new Error('MetaMask not detected. Install MetaMask to continue.');

    const chainIdHex = await window.ethereum.request({ method: 'eth_chainId' });
    const chainId    = Number(BigInt(chainIdHex));

    if (chainId !== NETWORK.chainId) {
      throw new Error(
        `Wrong network (chain ${chainId}). Switch MetaMask to Anvil — chain 31337, RPC: http://127.0.0.1:8545`
      );
    }

    const provider = new ethers.BrowserProvider(window.ethereum);
    const accounts = await provider.send('eth_requestAccounts', []);
    const signer   = await provider.getSigner();
    _baseUnitW = new ethers.Contract(NETWORK.baseUnit, BASE_UNIT_ABI, signer);
    _subUnitW  = new ethers.Contract(NETWORK.subUnit,  SUB_UNIT_ABI,  signer);
    return { address: accounts[0], chainId };
  }

  async function getBaseUnitConstants() {
    const [maxSupply, totalSupply, price, maxPerWallet] = await Promise.all([
      _baseUnit.MAX_SUPPLY(),
      _baseUnit.totalSupply(),
      _baseUnit.BASE_UNIT_PRICE(),
      _baseUnit.MAX_UNITS_PER_WALLET(),
    ]);
    return {
      maxSupply:    Number(maxSupply),
      totalSupply:  Number(totalSupply),
      priceEth:     ethers.formatEther(price),
      maxPerWallet: Number(maxPerWallet),
    };
  }

  async function getSubUnitConstants() {
    const [price, totalMinted, totalCompleted] = await Promise.all([
      _subUnit.SUB_UNIT_PRICE(),
      _subUnit.totalSubUnitsMinted(),
      _subUnit.totalCompleted(),
    ]);
    return {
      priceEth:       ethers.formatEther(price),
      totalMinted:    Number(totalMinted),
      totalCompleted: Number(totalCompleted),
    };
  }

  async function getUserBaseUnits(address) {
    const balance = Number(await _baseUnit.balanceOf(address));
    if (balance === 0) return [];

    const tokenIds = await Promise.all(
      Array.from({ length: balance }, (_, i) => _baseUnit.tokenOfOwnerByIndex(address, i))
    );

    const units = await Promise.all(tokenIds.map(async (rawId) => {
      const tokenId = Number(rawId);

      const [type, limit, subCount, score, completed, subUnitIds] = await Promise.all([
        _baseUnit.typeOf(tokenId),
        _baseUnit.subUnitLimitOf(tokenId),
        _subUnit.subUnitCountPerBase(tokenId),
        _subUnit.localScore(tokenId),
        _subUnit.isCompleted(tokenId),
        _subUnit.getSubUnitsForBase(tokenId),
      ]);

      const t        = Number(type);
      const lim      = Number(limit);
      const maxScore = (lim * (lim + 1)) / 2;

      const subUnits = await Promise.all(subUnitIds.map(async (rawSubId) => {
        const subId    = Number(rawSubId);
        const subScore = await _subUnit.subUnitScore(subId);
        return { tokenId: subId, score: Number(subScore), imageUri: '' };
      }));

      return {
        tokenId, type: t, typeName: TYPE_NAMES[t], limit: lim,
        maxScore, localScore: Number(score), subUnitCount: Number(subCount),
        isCompleted: completed, imageUri: '', subUnits,
      };
    }));

    return units;
  }

  async function getUserGlobalScore(address) {
    return Number(await _subUnit.globalScore(address));
  }

  async function getUserTypeBalances(address) {
    const balance = Number(await _baseUnit.balanceOf(address));
    if (balance === 0) return { 0: 0, 1: 0, 2: 0 };
    const tokenIds = await Promise.all(
      Array.from({ length: balance }, (_, i) => _baseUnit.tokenOfOwnerByIndex(address, i))
    );
    const types = await Promise.all(tokenIds.map(id => _baseUnit.typeOf(id)));
    const bal   = { 0: 0, 1: 0, 2: 0 };
    types.forEach(t => bal[Number(t)]++);
    return bal;
  }

  async function mintBaseUnit() {
    const price   = await _baseUnit.BASE_UNIT_PRICE();
    const tx      = await _baseUnitW.mintBaseUnit({ value: price });
    const receipt = await tx.wait();
    const iface   = new ethers.Interface(BASE_UNIT_ABI);
    for (const log of receipt.logs) {
      try {
        const parsed = iface.parseLog(log);
        if (parsed.name === 'BaseUnitMinted') {
          return { tokenId: Number(parsed.args.tokenId), txHash: receipt.hash };
        }
      } catch (_) { /* skip unparseable logs */ }
    }
    throw new Error('BaseUnitMinted event not found in receipt');
  }

  async function disconnectWallet() {
    _baseUnitW = null;
    _subUnitW  = null;
    if (window.ethereum) {
      await window.ethereum.request({
        method: 'wallet_revokePermissions',
        params: [{ eth_accounts: {} }],
      });
    }
  }

  async function mintSubUnit(baseUnitId) {
    const price   = await _subUnit.SUB_UNIT_PRICE();
    const tx      = await _subUnitW.mintSubUnit(baseUnitId, { value: price });
    const receipt = await tx.wait();
    const iface   = new ethers.Interface(SUB_UNIT_ABI);
    for (const log of receipt.logs) {
      try {
        const parsed = iface.parseLog(log);
        if (parsed.name === 'SubUnitMinted') {
          return { subUnitId: Number(parsed.args.subUnitId), txHash: receipt.hash };
        }
      } catch (_) { /* skip unparseable logs */ }
    }
    throw new Error('SubUnitMinted event not found in receipt');
  }

  // ── Export ───────────────────────────────────────────────────────────────────

  window.Api = {
    initNetwork,
    connectWallet,
    disconnectWallet,
    getBaseUnitConstants,
    getSubUnitConstants,
    getUserBaseUnits,
    getUserGlobalScore,
    getUserTypeBalances,
    mintBaseUnit,
    mintSubUnit,
  };

})();
