FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

# Install Helm
RUN curl https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz | tar -xz \
    && mv linux-amd64/helm /usr/local/bin/ \
    && rm -rf linux-amd64

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install age
RUN curl -LO "https://github.com/FiloSottile/age/releases/latest/download/age-$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep -Po '"tag_name": "v\K[^"]*')-linux-amd64.tar.gz" \
    && tar -xzf age-*.tar.gz \
    && mv age/age /usr/local/bin/ \
    && mv age/age-keygen /usr/local/bin/ \
    && rm -rf age age-*.tar.gz

# Install SOPS
RUN curl -LO "https://github.com/getsops/sops/releases/latest/download/sops-$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep -Po '"tag_name": "v\K[^"]*').linux.amd64" \
    && mv sops-*.linux.amd64 /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops

# Install Flux CLI
RUN curl -s https://fluxcd.io/install.sh | bash

# Install k9s
RUN curl -LO "https://github.com/derailed/k9s/releases/latest/download/k9s_$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep -Po '"tag_name": "v\K[^"]*')_Linux_amd64.tar.gz" \
    && tar -xzf k9s_*_Linux_amd64.tar.gz \
    && mv k9s /usr/local/bin/ \
    && rm k9s_*_Linux_amd64.tar.gz

# Install kubelogin
RUN curl -LO "https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-linux-amd64.zip" \
    && unzip kubelogin-linux-amd64.zip \
    && mv bin/linux_amd64/kubelogin /usr/local/bin/ \
    && rm -rf kubelogin-linux-amd64.zip bin

# Install Kyverno CLI
RUN curl -LO "https://github.com/kyverno/kyverno/releases/latest/download/kyverno-cli_$(curl -s https://api.github.com/repos/kyverno/kyverno/releases/latest | grep -Po '"tag_name": "v\K[^"]*')_linux_x86_64.tar.gz" \
    && tar -xzf kyverno-cli_*_linux_x86_64.tar.gz \
    && mv kyverno /usr/local/bin/ \
    && rm kyverno-cli_*_linux_x86_64.tar.gz

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
