"use client";

import { useEffect, useMemo } from "react";
import { useTheme } from "next-themes";
import { Abi, Address } from "viem";
import { useReadContract } from "wagmi";
import { formatEther } from "viem";
import { ArrowPathIcon } from "@heroicons/react/24/outline";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { getParsedError, notification } from "~~/utils/scaffold-eth";

type LotteryEntryFeeDisplayProps = {
  contractAddress: Address;
  contractAbi: Abi;
  refreshDisplayVariables: boolean;
};

export const LotteryEntryFeeDisplay = ({
  contractAddress,
  contractAbi,
  refreshDisplayVariables,
}: LotteryEntryFeeDisplayProps) => {
  const { targetNetwork } = useTargetNetwork();
  const { resolvedTheme } = useTheme();
  const isDarkMode = useMemo(() => resolvedTheme === "dark", [resolvedTheme]);

  const {
    data: lotteryEntryFeeResult,
    isFetching,
    refetch,
    error,
  } = useReadContract({
    address: contractAddress,
    functionName: "lotteryEntryFee",
    abi: contractAbi,
    chainId: targetNetwork.id,
    query: {
      enabled: !!contractAddress,
      retry: false,
    },
  });

  useEffect(() => {
    refetch();
  }, [refetch, refreshDisplayVariables]);

  useEffect(() => {
    if (error) {
      const parsedError = getParsedError(error);
      notification.error(parsedError);
    }
  }, [error]);

  const formatFee = (fee: bigint | undefined): string => {
    if (fee === undefined || fee === null) {
      return "--";
    }
    try {
      return formatEther(fee);
    } catch {
      return fee.toString();
    }
  };

  return (
    <div className="space-y-1 pb-2">
      <div className="flex items-center">
        <h3
          className="font-medium text-lg mb-0 break-all"
          style={{
            color: isDarkMode ? "#30B4ED" : "#30B4ED",
          }}
        >
          lotteryEntryFee
        </h3>
        <button className="btn btn-ghost btn-xs" onClick={async () => await refetch()}>
          {isFetching ? (
            <span className="loading loading-spinner loading-xs"></span>
          ) : (
            <ArrowPathIcon className="h-3 w-3 cursor-pointer" aria-hidden="true" />
          )}
        </button>
      </div>
      <div className="font-medium flex flex-col items-start">
        <div>
          <div
            className="break-all block transition bg-transparent"
            style={{
              color: isDarkMode ? "white" : "black",
            }}
          >
            {isFetching ? (
              <span className="loading loading-spinner loading-xs"></span>
            ) : (
              <>{formatFee(lotteryEntryFeeResult as bigint | undefined)} ETH</>
            )}
          </div>
        </div>
        <div
          className="text-xs mt-1"
          style={{
            color: isDarkMode ? "rgba(255, 255, 255, 0.5)" : "rgba(0, 0, 0, 0.5)",
          }}
        >
          Entry fee in ETH
        </div>
      </div>
    </div>
  );
};
