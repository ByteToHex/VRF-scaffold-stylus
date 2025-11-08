"use client";

import type { NextPage } from "next";

import NetworkWarning from "./_components/NetworkWarning";
import WhatIsChainlinkVRF from "./_components/WhatIsChainlinkVRF";
import VRFInteractions from "./_components/VRFInteractions";

const VRFPage: NextPage = () => {
  return (
    <div className="flex items-center flex-col justify-start flex-grow pt-10 px-4">
      <div className="max-w-4xl w-full">
        {/* Header */}
        <div className="text-center mb-8">
          <h1 className="text-4xl font-bold mb-4">Chainlink VRF Integration</h1>
          <p className="text-lg text-base-content/80">Verifiable Random Function (VRF) using Stylus Smart Contracts</p>
        </div>

        {/* Network Warning */}
        <NetworkWarning />

        {/* What is Chainlink VRF Section */}
        <WhatIsChainlinkVRF />

        {/* Interactions */}
        <VRFInteractions />
      </div>
    </div>
  );
};

export default VRFPage;
