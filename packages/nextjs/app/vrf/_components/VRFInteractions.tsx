"use client";

import { useState } from "react";
import { useAccount, useBalance } from "wagmi";
import { parseEther, formatEther } from "viem";
import { useScaffoldContract, useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";
import { useTransactor } from "~~/hooks/scaffold-eth/useTransactor";

const VRFInteractions = () => {
  const { address: connectedAddress } = useAccount();
  const tx = useTransactor();
  const [fundAmount, setFundAmount] = useState<string>("0.0001");
  const [isFunding, setIsFunding] = useState<boolean>(false);

  const { data: vrfContract } = useScaffoldContract({
    contractName: "vrf-consumer",
  });

  const { data: balanceData, refetch: refetchBalance } = useBalance({
    address: vrfContract?.address as `0x${string}`,
    query: { enabled: !!vrfContract?.address },
  });

  const { writeContractAsync: requestRandomWords, isMining: isRequestingRandom } = useScaffoldWriteContract({
    contractName: "vrf-consumer",
  });

  const { data: lastRequestId, refetch: refetchLastRequestId } = useScaffoldReadContract({
    contractName: "vrf-consumer",
    functionName: "getLastRequestId",
  });

  const { data: requestStatus, refetch: refetchStatus } = useScaffoldReadContract({
    contractName: "vrf-consumer",
    functionName: "getRequestStatus",
    args: [lastRequestId ? BigInt(lastRequestId) : undefined],
    watch: true,
  });

  const { data: requiredPriceData } = useScaffoldReadContract({
    contractName: "vrf-consumer",
    // getRequestPrice was recently added to the contract; cast to bypass outdated ABI typing
    functionName: "getRequestPrice" as any,
    watch: true,
  });
  const requiredPrice = requiredPriceData as unknown as bigint | null;

  const handleFund = async () => {
    if (!vrfContract?.address || !fundAmount) return;
    try {
      setIsFunding(true);
      await tx({
        to: vrfContract?.address as `0x${string}`,
        value: parseEther(fundAmount),
      });
      await refetchBalance();
    } catch (e) {
      // ignore, error shown via transactor
    } finally {
      setIsFunding(false);
    }
  };

  const handleRequest = async () => {
    try {
      await requestRandomWords({ functionName: "requestRandomWords" });
      await Promise.all([refetchLastRequestId(), refetchStatus(), refetchBalance()]);
    } catch (e) {
      // errors surfaced by wagmi notifications
    }
  };

  return (
    <div className="flex flex-col gap-6">
      {/* Left: Actions */}
      <div className="card bg-base-100 shadow-xl">
        <div className="card-body">
          <h2 className="card-title text-xl">Actions</h2>

          {/* Fund Contract */}
          <div className="bg-base-200 p-3 rounded-lg">
            <div className="flex items-center justify-between">
              <label className="label">
                <span className="label-text text-sm">Fund contract (ETH)</span>
              </label>
              <div className="text-right font-semibold">
                VRF Balance: {balanceData?.formatted || "0"} {balanceData?.symbol || "ETH"}
              </div>
            </div>
            <div className="flex items-center justify-between gap-2">
              <input
                type="number"
                min="0"
                step="0.001"
                className="input input-bordered w-full"
                value={fundAmount}
                onChange={e => setFundAmount(e.target.value)}
                placeholder="0.01"
              />
              <button
                className="btn btn-primary"
                onClick={handleFund}
                disabled={!connectedAddress || !vrfContract?.address || isFunding || Number(fundAmount) <= 0}
              >
                {isFunding ? <span className="loading loading-spinner loading-sm"></span> : "Fund"}
              </button>
            </div>
            <div className="flex flex-col gap-2 mt-2 text-xs text-base-content/80">
              {requiredPrice != null && (
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setFundAmount(formatEther(requiredPrice as bigint))}
                  title="Fill with required price"
                >
                  Fill required: {formatEther(requiredPrice as bigint)} ETH
                </button>
              )}
              <div className="alert alert-warning py-2 px-3 text-xs">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  className="stroke-current shrink-0 h-4 w-4"
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
                <span>You must fund the VRF contract so it has enough balance to execute requests.</span>
              </div>
            </div>
          </div>

          {/* Request Random Numbers */}
          <div className="bg-base-200 p-3 rounded-lg mt-3">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div className="min-w-0">
                <div className="font-semibold text-sm">Request Random Numbers</div>
                <div className="text-xs text-base-content/70">Calls contract to request randomness.</div>
              </div>
              <button
                className="btn btn-secondary"
                onClick={handleRequest}
                disabled={
                  isRequestingRandom ||
                  !connectedAddress ||
                  !vrfContract?.address ||
                  (requiredPrice != null && balanceData != null && balanceData.value < (requiredPrice as bigint))
                }
              >
                <span className="flex items-center gap-2">
                  {isRequestingRandom && <span className="loading loading-spinner loading-sm"></span>}
                  Request
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Right: Live Status */}
      <div className="card bg-base-100 shadow-xl">
        <div className="card-body">
          <h2 className="card-title text-xl">Live Status</h2>

          <div className="grid gap-3">
            <div className="bg-base-200 p-3 rounded-lg">
              <div className="text-xs text-base-content/70">Latest Request ID</div>
              <div className="flex items-center justify-between mt-1 gap-2">
                <code className="text-sm bg-base-300 px-2 py-1 rounded select-all cursor-pointer whitespace-nowrap overflow-x-auto max-w-full">
                  {lastRequestId ? lastRequestId.toString() : "—"}
                </code>
                <div className="flex items-center gap-1">
                  <button className="btn btn-xs btn-ghost" onClick={() => refetchLastRequestId()} title="Refresh">
                    🔄
                  </button>
                </div>
              </div>
            </div>

            <div className="bg-base-200 p-3 rounded-lg">
              <div className="text-xs text-base-content/70">Fulfilled</div>
              <div className="mt-1">
                <span className={`badge ${requestStatus && requestStatus[1] ? "badge-success" : "badge-warning"}`}>
                  {requestStatus && requestStatus[1] ? "Yes" : "Pending"}
                </span>
              </div>
            </div>

            <div className="bg-base-200 p-3 rounded-lg">
              <div className="text-xs text-base-content/70">Random Number</div>
              <code className="text-sm bg-base-300 px-2 py-1 rounded select-all cursor-pointer mt-1 block whitespace-nowrap overflow-x-auto">
                {requestStatus && requestStatus[2] ? requestStatus[2].toString() : "—"}
              </code>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VRFInteractions;
