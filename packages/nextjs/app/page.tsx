import { ERC20Interactions } from "./erc20/_components/ERC20Interactions";
import type { NextPage } from "next";
import { getMetadata } from "~~/utils/scaffold-eth/getMetadata";

export const metadata = getMetadata({
  title: "Lottery Token",
  description: "Interact with Lottery Token (LUK) contract",
});

const Home: NextPage = () => {
  return <ERC20Interactions />;
};

export default Home;
