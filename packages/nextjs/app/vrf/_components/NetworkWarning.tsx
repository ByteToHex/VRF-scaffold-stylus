const NetworkWarning = () => {
  return (
    <div className="alert alert-warning mb-8">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        className="stroke-current shrink-0 h-6 w-6"
        fill="none"
        viewBox="0 0 24 24"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
        />
      </svg>
      <div>
        <h3 className="font-bold">Network Compatibility Notice</h3>
        <div className="text-xs">
          Chainlink VRF contracts are only available on <strong>Arbitrum Sepolia</strong> and{" "}
          <strong>Arbitrum One</strong>. Make sure you&apos;re connected to one of these networks to interact with VRF
          services.
        </div>
        <div className="text-xs mt-2 p-2 rounded  border-black border">
          <strong>Setup (after you deploy the contracts):</strong> Update your
          <code className="bg-base-300 px-1 rounded text-base-content">scaffold.config.ts</code> to include
          <code className="bg-base-300 px-1 rounded text-base-content">chains.arbitrumSepolia</code> and/or
          <code className="bg-base-300 px-1 rounded text-base-content">chains.arbitrum</code> in the
          <code className="bg-base-300 px-1 rounded text-base-content">targetNetworks</code> array.
          <br />
          <br />
          <strong>Note:</strong> The VRF Consumer contract is deployed on Arbitrum Sepolia and Arbitrum One.
        </div>
      </div>
    </div>
  );
};

export default NetworkWarning;
