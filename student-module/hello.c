#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Student");
MODULE_DESCRIPTION("Simple Hello World kernel module");
MODULE_VERSION("1.0");

static int __init hello_init(void)
{
    pri ntk(KERN_INFO "Hello from kernel module!\n");
    return 0;
}

static void __exit hello_exit(void)
{
    printk(KERN_INFO "Goodbye from kernel module!\n");
}

module_init(hello_init);
