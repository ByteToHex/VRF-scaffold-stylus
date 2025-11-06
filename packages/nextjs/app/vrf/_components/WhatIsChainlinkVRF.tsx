const WhatIsChainlinkVRF = () => {
  return (
    <div className="card bg-base-100 shadow-xl mb-8">
      <div className="card-body">
        <h2 className="card-title text-2xl">What is Chainlink VRF?</h2>
        <p className="text-sm text-base-content/80 mt-2">
          A verifiable random number generator that provides tamper-proof randomness for smart contracts.
        </p>

        <div className="grid md:grid-cols-3 gap-3 mt-5">
          <div className="bg-base-200 p-4 rounded-lg">
            <div className="font-bold mb-1">🔒 Trustless</div>
            <div className="text-xs text-base-content/80">
              On-chain proofs ensure results can&apos;t be manipulated.
            </div>
          </div>
          <div className="bg-base-200 p-4 rounded-lg">
            <div className="font-bold mb-1">⚡ Simple</div>
            <div className="text-xs text-base-content/80">Request random numbers and verify with a single call.</div>
          </div>
          <div className="bg-base-200 p-4 rounded-lg">
            <div className="font-bold mb-1">💸 Pay-per-use</div>
            <div className="text-xs text-base-content/80">Direct funding model; pay only when you request.</div>
          </div>
        </div>

        <div className="alert alert-info mt-5">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            className="stroke-current shrink-0 w-6 h-6"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth="2"
              d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            ></path>
          </svg>
          <div className="text-xs">
            <a
              href="https://docs.chain.link/vrf/v2-5/direct-funding/get-a-random-number"
              target="_blank"
              rel="noopener noreferrer"
              className="link font-bold underline hover:no-underline"
            >
              Official VRF Direct Funding docs
            </a>
          </div>
        </div>
      </div>
    </div>
  );
};

export default WhatIsChainlinkVRF;
