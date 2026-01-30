# 🧪 Kernel Lab — Автоматическая проверка модулей ядра Linux через QEMU + GitHub Actions

1. 🏗️ собирает ядро Linux  
2. 📦 собирает BusyBox и формирует initramfs  
3. 🧩 собирает модуль студента  
4. 🚀 запускает QEMU  
5. 📜 из ядра извлекает JSON-отчёт  
6. ✔ проверяет, что модуль загружен и напечатал `Hello from kernel module!`

Если всё хорошо — CI зелёный.  
Если модуль не загрузился или не напечатал нужное сообщение — CI красный.

---

## 📦 Структура проекта

```
kernel-lab/
│
├── Dockerfile                 # Сборка ядра, initramfs и QEMU runtime
├── student-module/            # Модуль ядра, который предоставляет студент
│   ├── hello.c
│   └── Makefile
│
└── .github/workflows/
    └── kernel-test.yml        # GitHub Actions pipeline
```

---

# 🚀 Как работает система

### 1. Docker собирает всё окружение  
Dockerfile скачивает Linux 5.10.201, компилирует ядро, собирает BusyBox, формирует initramfs.

### 2. В initramfs встроен скрипт `/init`  
Он:
- монтирует `/proc`, `/sys`
- загружает модуль `insmod`
- собирает вывод `dmesg`
- печатает JSON блок:
  ```json
  {"status":"ok","message":"MODULE LOAD OK"}
  ```
- выключает виртуальную машину (`poweroff -f`)

### 3. GitHub Actions анализирует лог QEMU  
Он:
- извлекает JSON между `===RESULT===` и `===END===`
- проверяет поле `"status"`
- проверяет, что есть строка `"Hello from kernel module"`

---

# 🧩 Требования к модулю студента

## hello.c
```c
#include <linux/module.h>
#include <linux/kernel.h>

static int __init hello_init(void)
{
    printk(KERN_INFO "Hello from kernel module!\n");
    return 0;
}

static void __exit hello_exit(void)
{
    printk(KERN_INFO "Goodbye from kernel module!\n");
}

module_init(hello_init);
module_exit(hello_exit);

MODULE_LICENSE("GPL");
```

## Makefile
```make
obj-m += hello.o

all:
    make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
    make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
```

Студент может изменить названия файлов — CI сам возьмёт `*.ko`.

---

# 🔄 GitHub Actions — полный workflow

```yaml
name: kernel-module-test

on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repo
      uses: actions/checkout@v4

    - name: Install tooling
      run: |
        sudo apt update
        sudo apt install -y jq docker.io

    - name: Build kernel lab Docker image
      run: docker build -t kernel-lab .

    - name: Run kernel tests in QEMU
      run: |
        docker run --rm kernel-lab | tee qemu.log

    - name: Extract JSON and validate
      run: |
        RAW_OUTPUT="$(cat qemu.log)"

        echo "=== RAW OUTPUT ==="
        echo "$RAW_OUTPUT"

        JSON=$(echo "$RAW_OUTPUT" | sed -n '/===RESULT===/{n;/===END===/q;p;}')

        echo "=== PARSED JSON ==="
        echo "$JSON"

        STATUS=$(echo "$JSON" | jq -r '.status')

        if [[ "$STATUS" != "ok" ]]; then
            echo "❌ Module failed to load"
            exit 1
        fi

        if ! echo "$RAW_OUTPUT" | grep -q "Hello from kernel module"; then
            echo "❌ Module loaded but did NOT print hello"
            exit 1
        fi

        echo "✅ Module printed hello and loaded OK"
```

---

# 🖥 Локальный запуск

```
docker build -t kernel-lab .
docker run --rm kernel-lab
```

---

# 📊 Формат результата

### ✔ Успех
```
{"status":"ok","message":"MODULE LOAD OK"}
```

### ❌ Ошибка загрузки
```
{"status":"error","message":"MODULE LOAD FAILED","insmod_err":"invalid module format"}
```

---
