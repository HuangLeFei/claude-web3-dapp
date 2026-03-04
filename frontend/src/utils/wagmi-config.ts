import { http, createConfig } from "wagmi";
import { mainnet, sepolia, polygon, arbitrum, base } from "wagmi/chains";
import { injected, walletConnect, coinbaseWallet } from "wagmi/connectors";

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID!;

export const wagmiConfig = createConfig({
  chains: [mainnet, sepolia, polygon, arbitrum, base],
  connectors: [
    injected(),
    walletConnect({ projectId }),
    coinbaseWallet({ appName: "My DApp" }),
  ],
  transports: {
    [mainnet.id]: http(process.env.NEXT_PUBLIC_MAINNET_RPC_URL),
    [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL),
    [polygon.id]: http(),
    [arbitrum.id]: http(),
    [base.id]: http(),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
