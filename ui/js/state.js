(function () {
  'use strict';

  /**
   * @typedef {Object} SubUnit
   * @property {number} tokenId
   * @property {number} score
   * @property {string} imageUri
   */

  /**
   * @typedef {Object} BaseUnit
   * @property {number}    tokenId
   * @property {number}    type         — 0=A UNIT, 1=B UNIT, 2=C UNIT
   * @property {string}    typeName     — "A UNIT" | "B UNIT" | "C UNIT"
   * @property {number}    limit        — slot count: 4 | 6 | 8
   * @property {number}    maxScore     — limit*(limit+1)/2
   * @property {number}    localScore
   * @property {number}    subUnitCount
   * @property {boolean}   isCompleted
   * @property {string}    imageUri
   * @property {SubUnit[]} subUnits
   */

  /**
   * @typedef {Object} AppState
   * @property {boolean}          connected
   * @property {string|null}      userAddress
   * @property {string|null}      userAddressShort
   * @property {number}           globalScore
   * @property {number}           baseUnitsOwned
   * @property {number}           maxPerWallet
   * @property {number}           totalSupply
   * @property {number}           maxSupply
   * @property {string}           baseUnitPriceEth
   * @property {string}           subUnitPriceEth
   * @property {{0:number,1:number,2:number}} typeBalances
   * @property {BaseUnit[]}       baseUnits
   * @property {string}           activeView   — "intro" | "base" | "about"
   * @property {number|null}      selectedBaseIndex
   * @property {boolean}          loading
   * @property {string|null}      error
   */

  window.State = {
    connected: false,
    userAddress: null,
    userAddressShort: null,
    globalScore: 0,
    baseUnitsOwned: 0,
    maxPerWallet: 5,
    totalSupply: 0,
    maxSupply: 0,
    baseUnitPriceEth: '0',
    subUnitPriceEth: '0',
    typeBalances: { 0: 0, 1: 0, 2: 0 },
    baseUnits: [],
    activeView: 'intro',
    selectedBaseIndex: 0,
    chainId: null,
    loading: false,
    error: null,
    get selectedBase() {
      return this.baseUnits.length ? (this.baseUnits[this.selectedBaseIndex] ?? null) : null;
    },
    shortAddr(addr) {
      if (!addr) return '---';
      return addr.slice(0, 6) + '...' + addr.slice(-4);
    },
  };
})();
