## 一键脚本：

CF-DNS方式（推荐）：
```
bash <(curl -sL https://raw.githubusercontent.com/qichiyuhub/auto-ssl-cert/refs/heads/main/cloudflare.sh)
```
仅支持debeian/ubuntu- CF，脚本针对singbox写的，其他用途自行修改，singbox配置也可以直接配置API申请，根据自己情况选择。

HTTP方式：
```
bash <(curl -sL https://raw.githubusercontent.com/qichiyuhub/auto-ssl-cert/refs/heads/main/setup.sh)
```
支持debian/ubuntu/centos/rhel，但是使用上有要求，不建议使用。


以上不能满足可使用以下脚本，作者：Andy  
https://github.com/Lanlan13-14/Cert-Easy

或者自行github或者谷歌！