# Seblak Origin: Panduan Peluncuran Mint

Chain: **Robinhood Chain** (chain ID 4663), gas dibayar dengan ETH.
Wallet owner: `0xd65ebde9885e4c0578fbd97b88fb3a00595be4cb`

| Kontrak | Alamat |
|---|---|
| SBLor (token) | `0x3085510A066Fde9F60B5F732814d38D3cAccEAa3` |
| Seblak Agents (NFT) | `0xd32fe175A0FB38F44382F78e1c6717f314e4a2A9` |
| Seblak Mine | `0xd9927A5d63bE1d0Ba162148D83CF5e23ae664b52` |
| Seblak Market | `0xf3A5E8B8e6Cb6d8aA303e4C194A2B998cFd27ACf` |

> **Penting:** setiap langkah di bawah ini **dikirim sendiri oleh Anda dari wallet owner** setelah Anda
> memeriksanya. Hark tidak pernah menandatangani atau mengirim transaksi sungguhan. Seluruh urutan ini
> sudah diuji di **fork anvil** dari mainnet (blok 96.595.729, 24 Okt 2026) dan semua langkah berhasil.
> Hasil di fork: status Open, pool 30M, rilis/jam ≈ 600.000, minted 1/10.000.

Cara kirim: lewat MetaMask/Rabby gunakan fitur "kirim data hex" ke alamat target dengan nilai 0 ETH,
atau dengan Foundry (`cast send <target> <calldata> --rpc-url https://rpc.mainnet.chain.robinhood.com`
dari wallet owner Anda sendiri). Kerjakan **langkah 1 sampai 4 berturut-turut tanpa jeda**.

---

## Langkah 1: `Mine.update()` (selagi pool masih 0)

- **Target:** Seblak Mine `0xd9927A5d63bE1d0Ba162148D83CF5e23ae664b52`
- **Fungsi:** `update()`
- **Calldata:** `0xa2e62045`
- **Estimasi gas:** 41.139

Gunanya: menyetel ulang `lastUpdate` ke waktu sekarang selagi pool masih kosong (rilis = 0).
**Wajib dilakukan sebelum langkah 2.** Lihat catatan "lastUpdate basi" di bawah.

## Langkah 2: `SBLor.transfer(Mine, 30.000.000 SBLor)`

- **Target:** SBLor `0x3085510A066Fde9F60B5F732814d38D3cAccEAa3`
- **Fungsi:** `transfer(address,uint256)` dengan `to = 0xd9927A5d63bE1d0Ba162148D83CF5e23ae664b52`, `amount = 30000000e18`
- **Calldata:**
  `0xa9059cbb000000000000000000000000d9927a5d63be1d0ba162148d83cf5e23ae664b5200000000000000000000000000000000000000000018d0bf423c03d8de000000`
- **Estimasi gas:** 52.238

## Langkah 3: `Agents.setMintEnabled(true)` (langsung sesudahnya)

- **Target:** Seblak Agents `0xd32fe175A0FB38F44382F78e1c6717f314e4a2A9`
- **Fungsi:** `setMintEnabled(bool)` dengan `true`
- **Calldata:** `0xf46a04eb0000000000000000000000000000000000000000000000000000000000000001`
- **Estimasi gas:** 48.571

Halaman mint otomatis berubah ke "Mint is live" begitu langkah ini masuk.

## Langkah 4 (disarankan): owner langsung mint 1 agent

Selama belum ada agent, rilis dari pool menumpuk di `backlog` dan **seluruhnya jatuh ke miner pertama**.
Dengan mint segera, tumpukan itu Anda tangkap sendiri dan bukan orang yang kebetulan pertama.
Wallet owner sudah memegang ERC-8004 Agent ID (estimasi `mint` di fork berhasil) dan merupakan EOA.

4a. **Approve**
- **Target:** SBLor `0x3085510A066Fde9F60B5F732814d38D3cAccEAa3`
- **Fungsi:** `approve(address,uint256)` dengan `spender = 0xd32fe175A0FB38F44382F78e1c6717f314e4a2A9`, `amount = 1000e18`
- **Calldata:** `0x095ea7b3000000000000000000000000d32fe175a0fb38f44382f78e1c6717f314e4a2a900000000000000000000000000000000000000000000003635c9adc5dea00000`
- **Estimasi gas:** 46.968

4b. **Mint**
- **Target:** Seblak Agents `0xd32fe175A0FB38F44382F78e1c6717f314e4a2A9`
- **Fungsi:** `mint(string directive)`. Directive maksimal 120 karakter ASCII, tanpa `" \ < > &` dan tanpa emoji.
- **Calldata (directive kosong):**
  `0xd85d3d2700000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000`
- **Calldata (contoh directive "Level 5, no mercy"):**
  `0xd85d3d27000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000114c6576656c20352c206e6f206d65726379000000000000000000000000000000`
- Untuk directive lain: `cast calldata 'mint(string)' 'teks Anda'`
- **Estimasi gas:** ±364.000 (kosong) sampai ±392.000 (dengan directive)

Atau cukup lakukan 4a dan 4b lewat halaman mint (Connect wallet, lalu Approve, lalu Mint).

## Langkah 5 (opsional): ubah harga mint

- **Target:** Seblak Agents, fungsi `setMintPrice(uint256)` (dalam satuan wei SBLor, 18 desimal)
- Harga sekarang: 1.000 SBLor. Contoh 2.000 SBLor (`2000e18`):
  `0xf4a0a52800000000000000000000000000000000000000000000006c6b935b8bbd400000`
- **Estimasi gas:** ±29.000
- Tidak ada batas atas atau bawah di kontrak, jadi periksa angkanya dua kali.

## Langkah 6: likuiditas (nanti)

Tambahkan likuiditas SBLor/ETH di DEX **setelah** mint berjalan dan harga mint terasa wajar. Ini belum
disiapkan dan belum diuji. Hitung dulu berapa SBLor yang dialokasikan supaya tidak bertabrakan dengan pool Mine.

## Langkah 7: hosting halaman

Folder `mintapp/` adalah situs statis (index.html, ethers.min.js, gambar). Tidak perlu build.
- **Wajib HTTPS**: wallet seperti MetaMask (terutama mobile/in-app browser) butuh situs https.
- Pilihan: **Vercel** atau **Netlify** (drag-and-drop folder), **GitHub Pages** (push ke repo, aktifkan Pages),
  atau **IPFS** (misalnya Pinata atau Fleek, lalu akses lewat gateway https atau domain ENS).
- Tombol "Open in MetaMask" memakai `metamask.app.link/dapp/<host>/<path>`, jadi pastikan domain final sudah https.
- Parameter `?rpc=` hanya untuk pengujian lokal. Jangan dibagikan.

---

## Gas vs saldo owner

Harga gas mainnet saat pengecekan: **0,020188 gwei** (20.188.000 wei).

| Langkah | Gas (estimasi) | Biaya ≈ ETH |
|---|---|---|
| 1 update() | 41.139 | 0,00000083 |
| 2 transfer 30M | 52.238 | 0,00000105 |
| 3 setMintEnabled | 48.571 | 0,00000098 |
| 4a approve | 46.968 | 0,00000095 |
| 4b mint | ±392.468 | 0,00000792 |
| **Total 1–4** | **±581.384** | **≈ 0,0000117** |
| 5 setMintPrice (opsional) | ±29.293 | 0,00000059 |

Saldo owner: **≈ 0,000309 ETH**, sekitar **26×** total biaya. Masih aman walau wallet mencadangkan
batas biaya 2–3× lebih tinggi. Gas di fork (gasUsed nyata): update 38.782, transfer 51.638,
setMintEnabled 48.012, approve 46.379, mint 446.706 (mint pertama sedikit lebih mahal karena
menulis storage baru). Harga gas bisa naik, jadi cek lagi tepat sebelum mengirim.

---

## Catatan dan risiko

1. **lastUpdate basi.** `lastUpdate` di Mine masih dari waktu deploy. Rilis dihitung linear:
   `pool × 2% × jam sejak lastUpdate`. Kalau pool diisi **tanpa** `update()` lebih dulu, miner pertama
   langsung mendapat ±600.000 SBLor untuk **setiap jam** sejak deploy (saat diuji ±21 jam, jadi ±12,6 juta
   SBLor; perkiraan sebelumnya 10,32 juta, dan angkanya terus bertambah, maksimal seluruh pool).
   Karena itu langkah 1 wajib dilakukan sebelum langkah 2.
2. **Laju rilis 2%/jam dari sisa pool.** Dengan pool 30 juta: ±600.000 di jam pertama, ±11,5–11,6 juta
   di hari pertama, ±29 juta di minggu pertama. Waktu paruh ±34 jam, jadi pool cepat terkuras. Untuk
   emisi yang lebih panjang, siapkan **top-up**: transfer SBLor tambahan ke Mine kapan saja. Fee 3%
   dari Market juga masuk ke pool. Kalau Mine sudah lama tidak di-update sebelum top-up, panggil
   `update()` dulu supaya top-up tidak ikut dihitung untuk jam-jam yang lewat.
3. **Wallet smart-contract tidak bisa mint** (`msg.sender == tx.origin`). Safe/multisig, akun AA,
   dan sebagian embedded wallet akan gagal dengan `NoContracts`. Hanya EOA biasa yang bisa mint.
   Peminter juga wajib memegang ERC-8004 Agent ID, dengan batas 10 per wallet dan suplai 10.000.
4. **Tier pseudo-acak.** Tier dihitung dari `prevrandao`, blockhash, timestamp, alamat, dan id. Ini tidak
   bisa diprediksi pengguna biasa, tetapi juga bukan VRF: sequencer/validator secara teori bisa
   memengaruhinya. Sampaikan apa adanya ke komunitas (4% Sultan 9×, 16% Level Pedas 3×, 80% Kerupuk 1×).
5. **Listing market basi.** Kalau agent dipindah atau approval dicabut setelah di-list, listing tetap
   tercatat di kontrak tetapi `buy` akan revert dengan `Stale`. Halaman menandai listing seperti itu sebagai
   tidak valid. Penjual sebaiknya membatalkan listing sebelum memindahkan agent.
6. Harga mint (`setMintPrice`) bisa diubah owner kapan saja tanpa batas, jadi umumkan setiap perubahan.
