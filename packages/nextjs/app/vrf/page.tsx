"use client";

import { useState } from "react";
import type { NextPage } from "next";

import { useAccount, useChainId } from "wagmi";
import NetworkWarning from "./_components/NetworkWarning";
import WhatIsChainlinkVRF from "./_components/WhatIsChainlinkVRF";
import VRFInteractions from "./_components/VRFInteractions";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import { arbitrum, arbitrumSepolia } from "viem/chains";

const ARB_SEPOLIA_CONSUMER_ADDRESS = "0xeEA5eC3da1ED9b3479Cb2f0834f4FD918eBCfCC2";
const ARB_MAINNET_CONSUMER_ADDRESS = "0x0000000000000000000000000000000000000000";

const VRFPage: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const chainId = useChainId();

  // State for VRF Consumer contract address
  const [vrfConsumerAddress] = useState<string>(() => {
    if (chainId === arbitrumSepolia.id) {
      return ARB_SEPOLIA_CONSUMER_ADDRESS;
    } else if (chainId === arbitrum.id) {
      return ARB_MAINNET_CONSUMER_ADDRESS;
    }
    return "";
  });
  const [requestId, setRequestId] = useState<string>("");

  // Contract interactions
  const { writeContractAsync: requestRandomWords, isMining: isRequestingRandom } = useScaffoldWriteContract({
    contractName: "vrf-consumer",
  });

  const { data: lastRequestId, refetch: refetchLastRequestId } = useScaffoldReadContract({
    contractName: "vrf-consumer",
    functionName: "getLastRequestId",
  });

  const { data: requestStatus } = useScaffoldReadContract({
    contractName: "vrf-consumer",
    functionName: "getRequestStatus",
    args: [lastRequestId ? BigInt(lastRequestId) : undefined],
    watch: true,
  });

  const handleRequestRandomWords = async () => {
    try {
      await requestRandomWords({
        functionName: "requestRandomWords",
      });
    } catch (error) {
      console.error("Error requesting random numbers:", error);
    }
  };

  const handleCheckStatus = () => {
    if (lastRequestId) {
      setRequestId(lastRequestId.toString());
    }
  };

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
