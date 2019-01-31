## ETH Giveaway

Testnet private key: cP7453tMvkWPcEHfx8zpCQezoU5PeoQjjEYaCMzxD9Tz4f5GEpxW
Address: tb1qj7mtznsd6uzmztma6yutkklv4ypjj4g9mhmmf4

Asset ID: 6f840761c0b7d0af3514c4577af80899b65a1bf2c7d022a6c0c58afa2f8f2bc9

The above address contains 10 Finney worth of "stablecoin".

## Redeem process

Install Bitcoin Core and launch with `-testnet -server=1 -rpcuser=bitcoin -rpcpassword=bitcoin`.

Install [Kaleidoscope](https://github.com/rgb-org/kaleidoscope) and create `~/.rgb/rgb.conf`:

```json
{
    "rpcconnect": "127.0.0.1",
    "rpcport": 18332,
    "rpcuser": "bitcoin",
    "rpcpassword": "bitcoin",
    "default_server": "localhost:3000"
}
```

Install [Bitfröst](https://github.com/rgb-org/bifrost), create `~/.rgb-server` and extract `rgb-server.zip`,
which contains the proofs you need in order to spend the stablecoin.

Send up to 10 finney to me at `tb1q4fnez58x6nqrjvyx7hrp8g92wc9ne439jag2ns@localhost:3000` and email the generated proof to `sjors@sprovoost.nl` as well as your ETH address.
