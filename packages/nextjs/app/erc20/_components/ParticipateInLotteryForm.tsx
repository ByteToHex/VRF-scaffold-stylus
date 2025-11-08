"use client";

import { useEffect, useMemo, useState } from "react";
import { useTheme } from "next-themes";
import { Abi, Address, TransactionReceipt } from "viem";
import {
  useAccount,
  useConfig,
  useReadContract,
  useWaitForTransactionReceipt,
  useWalletClient,
  useWriteContract,
} from "wagmi";
import { useTransactor } from "~~/hooks/scaffold-eth";
import { useTargetNetwork } from "~~/hooks/scaffold-eth/useTargetNetwork";
import { AllowedChainIds } from "~~/utils/scaffold-stylus";
import { simulateContractWriteAndNotifyError, getParsedErrorWithAllAbis } from "~~/utils/scaffold-eth/contract";
import { notification } from "~~/utils/scaffold-eth";
import { TxReceipt } from "~~/app/debug/_components/contract";

type ParticipateInLotteryFormProps = {
  contractAddress: Address;
  contractAbi: Abi;
  onChange: () => void;
};

export const ParticipateInLotteryForm = ({ contractAddress, contractAbi, onChange }: ParticipateInLotteryFormProps) => {
  const { address, chain, isConnected } = useAccount();
  const { data: walletClient } = useWalletClient();
  const writeTxn = useTransactor();
  const { targetNetwork } = useTargetNetwork();
  const { resolvedTheme } = useTheme();
  const isDarkMode = useMemo(() => resolvedTheme === "dark", [resolvedTheme]);

  const { data: result, isPending, writeContractAsync } = useWriteContract();
  const wagmiConfig = useConfig();

  // Get lotteryEntryFee
  const { data: lotteryEntryFee } = useReadContract({
    address: contractAddress,
    functionName: "lotteryEntryFee",
    abi: contractAbi,
    chainId: targetNetwork.id,
    query: {
      enabled: !!contractAddress,
    },
  });

  // Debug: Check each condition (after lotteryEntryFee is declared)
  const isWalletConnected = isConnected && !!address;
  const isCorrectNetwork = chain && chain.id === targetNetwork.id;
  const hasWalletClient = !!walletClient;
  const hasEntryFee = !!lotteryEntryFee;

  const writeDisabled = !isWalletConnected || !isCorrectNetwork || !hasWalletClient;

  // Create helpful tooltip message
  const getTooltipMessage = () => {
    if (!isWalletConnected) return "Please connect your wallet";
    if (!isCorrectNetwork)
      return `Wrong network. Please switch to ${targetNetwork.name} (Chain ID: ${targetNetwork.id}). Current: ${chain?.name || "Unknown"} (Chain ID: ${chain?.id || "Unknown"})`;
    if (!hasWalletClient) return "Wallet client not ready. Please wait...";
    if (!hasEntryFee) return "Loading entry fee...";
    return "";
  };

  const [displayedTxResult, setDisplayedTxResult] = useState<TransactionReceipt>();
  const { data: txResult } = useWaitForTransactionReceipt({
    hash: result,
  });

  // Separate state for request resolution transaction
  const [resultResolution, setResultResolution] = useState<`0x${string}` | undefined>();
  const { data: txResultResolution } = useWaitForTransactionReceipt({
    hash: resultResolution,
  });
  const [displayedTxResultResolution, setDisplayedTxResultResolution] = useState<TransactionReceipt>();
  const [isPendingResolution, setIsPendingResolution] = useState(false);

  useEffect(() => {
    setDisplayedTxResult(txResult);
  }, [txResult]);

  useEffect(() => {
    setDisplayedTxResultResolution(txResultResolution);
    if (txResultResolution) {
      setIsPendingResolution(false);
    }
  }, [txResultResolution]);

  const handleParticipate = async () => {
    if (!isConnected || !address) {
      notification.error("Please connect your wallet");
      return;
    }

    if (!writeContractAsync || !lotteryEntryFee) {
      notification.error("Contract not ready. Please wait...");
      return;
    }

    try {
      const writeContractObj: any = {
        address: contractAddress,
        functionName: "participateInLottery",
        abi: contractAbi,
        args: [],
        value: lotteryEntryFee as bigint,
      };

      try {
        await simulateContractWriteAndNotifyError({
          wagmiConfig,
          writeContractParams: writeContractObj,
          chainId: targetNetwork.id as AllowedChainIds,
        });
      } catch (simError: any) {
        // Check if simulation failed due to revert
        const isSimRevert =
          simError?.message?.includes("revert") ||
          simError?.message?.includes("reverted") ||
          simError?.shortMessage?.includes("revert") ||
          simError?.shortMessage?.includes("reverted") ||
          simError?.message?.includes("0x416c7265") ||
          simError?.shortMessage?.includes("0x416c7265");

        if (isSimRevert) {
          notification.error("Unable to participate in lottery. Have you already joined the current one?");
          return;
        }
        // Re-throw if it's not a revert error
        throw simError;
      }

      const makeWriteWithParams = () => writeContractAsync(writeContractObj);
      await writeTxn(makeWriteWithParams);
      onChange();
    } catch (e: any) {
      console.error("⚡️ ~ file: ParticipateInLotteryForm.tsx:handleParticipate ~ error", e);

      // Check if this is a transaction revert or error
      const isRevertError =
        e?.message?.includes("revert") ||
        e?.message?.includes("reverted") ||
        e?.shortMessage?.includes("revert") ||
        e?.shortMessage?.includes("reverted") ||
        e?.cause?.message?.includes("revert") ||
        e?.cause?.message?.includes("reverted") ||
        e?.walk?.()?.message?.includes("revert") ||
        e?.walk?.()?.message?.includes("reverted");

      // Check for the specific error signature 0x416c7265 (likely AlreadyParticipated or similar)
      const hasErrorSignature =
        e?.message?.includes("0x416c7265") ||
        e?.shortMessage?.includes("0x416c7265") ||
        e?.cause?.message?.includes("0x416c7265");

      if (isRevertError || hasErrorSignature) {
        notification.error("Unable to participate in lottery. Have you already joined the current one?");
      } else {
        // For other errors (network issues, etc.), show the parsed error
        const parsedError = getParsedErrorWithAllAbis(e, targetNetwork.id as AllowedChainIds);
        notification.error(parsedError);
      }
    }
  };

  const handleRequestResolution = async () => {
    if (!isConnected || !address) {
      notification.error("Please connect your wallet");
      return;
    }

    if (!writeContractAsync) {
      notification.error("Contract not ready. Please wait...");
      return;
    }

    setIsPendingResolution(true);
    try {
      const writeContractObj: any = {
        address: contractAddress,
        functionName: "requestRandomWords",
        abi: contractAbi,
        args: [],
      };

      try {
        await simulateContractWriteAndNotifyError({
          wagmiConfig,
          writeContractParams: writeContractObj,
          chainId: targetNetwork.id as AllowedChainIds,
        });
      } catch (simError: any) {
        setIsPendingResolution(false);
        // Re-throw simulation errors to be handled below
        throw simError;
      }

      const makeWriteWithParams = async () => {
        const hash = await writeContractAsync(writeContractObj);
        setResultResolution(hash);
        return hash;
      };
      await writeTxn(makeWriteWithParams);
      onChange();
    } catch (e: any) {
      setIsPendingResolution(false);
      console.error("⚡️ ~ file: ParticipateInLotteryForm.tsx:handleRequestResolution ~ error", e);
      const parsedError = getParsedErrorWithAllAbis(e, targetNetwork.id as AllowedChainIds);
      notification.error(parsedError);
    }
  };

  return (
    <div className="py-8 space-y-6 first:pt-0 last:pb-1">
      <div className="flex flex-col gap-6">
        <div>
          <h2
            className="my-0 break-words"
            style={{
              color: isDarkMode ? "#30B4ED" : "#30B4ED",
              fontSize: "2rem",
              fontWeight: "800",
              lineHeight: "1.2",
              marginBottom: "0.5rem",
            }}
          >
            Participate In Lottery
          </h2>
          <div
            className="text-base leading-relaxed"
            style={{
              color: isDarkMode ? "rgba(255, 255, 255, 0.7)" : "rgba(0, 0, 0, 0.7)",
              marginTop: "0.75rem",
              fontSize: "1.125rem",
            }}
          >
            <p className="mb-2">
              Join the decentralized lottery pool powered by Chainlink VRF for provably fair random selection. Each
              participation requires a fixed entry fee in ETH and grants you a chance to win the accumulated prize pool.
              Winners are selected through verifiable random functions, ensuring complete transparency and fairness in
              the selection process.
            </p>
            <p className="mb-0">
              Your Ethereum Tokens (ETH) can be used to enter sweepstakes. The reward is denominated in Lottery Token
              (LUK), which is autimatically awarded every drawing cycle, with winners announced upon VRF fulfillment.
            </p>
          </div>
        </div>
        <div className="flex flex-col gap-4">
          {displayedTxResult && (
            <div className="w-full">
              <TxReceipt txResult={displayedTxResult} />
            </div>
          )}
          <div className="flex flex-col gap-3">
            {/* Debug info - remove in production if desired */}
            {(writeDisabled || !hasEntryFee) && (
              <div className="text-xs text-base-content/60 p-2 bg-base-200 rounded">
                <div>Status: {isWalletConnected ? "✓ Connected" : "✗ Not Connected"}</div>
                <div>
                  Network:{" "}
                  {isCorrectNetwork
                    ? `✓ ${chain?.name} (${chain?.id})`
                    : `✗ ${chain?.name || "None"} (${chain?.id || "None"}) → Need ${targetNetwork.name} (${targetNetwork.id})`}
                </div>
                <div>Wallet Client: {hasWalletClient ? "✓ Ready" : "✗ Not Ready"}</div>
                <div>Entry Fee: {hasEntryFee ? "✓ Loaded" : "✗ Loading..."}</div>
              </div>
            )}
            <div className="flex flex-col gap-3 items-center">
              <div
                className={`flex ${
                  (writeDisabled || !hasEntryFee) &&
                  "tooltip tooltip-bottom tooltip-secondary before:content-[attr(data-tip)] before:-translate-x-1/3 before:left-auto before:transform-none"
                }`}
                data-tip={getTooltipMessage() || undefined}
              >
                <button
                  className="btn btn-primary btn-lg px-8 py-4 font-bold"
                  style={{
                    minWidth: "200px",
                    minHeight: "60px",
                    fontSize: "1.5rem",
                  }}
                  disabled={writeDisabled || isPending || !lotteryEntryFee}
                  onClick={handleParticipate}
                >
                  {isPending ? <span className="loading loading-spinner loading-md"></span> : "Participate in Lottery"}
                </button>
              </div>
              {displayedTxResultResolution && (
                <div className="w-full">
                  <TxReceipt txResult={displayedTxResultResolution} />
                </div>
              )}
              <div
                className={`flex ${
                  writeDisabled &&
                  "tooltip tooltip-bottom tooltip-secondary before:content-[attr(data-tip)] before:-translate-x-1/3 before:left-auto before:transform-none"
                }`}
                data-tip={getTooltipMessage() || undefined}
              >
                <button
                  className="btn btn-secondary btn-lg px-8 py-4 font-bold"
                  style={{
                    minWidth: "200px",
                    minHeight: "60px",
                    fontSize: "1.5rem",
                  }}
                  disabled={writeDisabled || isPendingResolution}
                  onClick={handleRequestResolution}
                >
                  {isPendingResolution ? (
                    <span className="loading loading-spinner loading-md"></span>
                  ) : (
                    "Request Lottery Resolution"
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
