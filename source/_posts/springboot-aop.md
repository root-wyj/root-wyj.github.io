---
title: SpringBoot-AOP
categories:
  - SpringBoot
tags:
  - springboot
  - 源码分析
  - aop
---


# SpringBoot-AOP

- [SpringBoot-AOP](#springboot-aop)
  - [组件了解](#%e7%bb%84%e4%bb%b6%e4%ba%86%e8%a7%a3)
    - [AbstractAutoProxyCreator](#abstractautoproxycreator)
    - [Advisor, Advice 与 Pointcut](#advisor-advice-%e4%b8%8e-pointcut)
  - [源码分析](#%e6%ba%90%e7%a0%81%e5%88%86%e6%9e%90)
    - [自动装配-创建`AnnotationAwareAspectJAutoProxyCreator`](#%e8%87%aa%e5%8a%a8%e8%a3%85%e9%85%8d-%e5%88%9b%e5%bb%baannotationawareaspectjautoproxycreator)
    - [找Advisor](#%e6%89%beadvisor)
    - [创建与执行代理-Proxy](#%e5%88%9b%e5%bb%ba%e4%b8%8e%e6%89%a7%e8%a1%8c%e4%bb%a3%e7%90%86-proxy)
  - [说在最后](#%e8%af%b4%e5%9c%a8%e6%9c%80%e5%90%8e)

<br>

## 组件了解

### AbstractAutoProxyCreator

首先看类图：

![|center](/images/springboot-aop-classmap-aaaapc.png)


**`AbstractAutoProxyCreator`**

最主要的类了，使用AOP创建代理的核心类。看一些成员变量：
- `protected static final Object[] DO_NOT_PROXY = null;` 不创建代理的返回
- `protected static final Object[] PROXY_WITHOUT_ADDITIONAL_INTERCEPTORS = new Object[0];` 返回这个表示 只使用 commonAdvisor 就可以了
- `private AdvisorAdapterRegistry advisorAdapterRegistry = GlobalAdvisorAdapterRegistry.getInstance();` 用来包装`Advisor`的，对各种类型的advisor做处理，某些需要特殊处理的，可以向里面注册 `AdvisorAdapter`，用它来包装advisor
  
  具体可以看方法 `AbstractAutoProxyCreator.buildAdvisors` 和 `DefaultAdvisorAdapterRegistry.warp`
- `private String[] interceptorNames = new String[0];` 设置common interceptor。默认是没有的。都是 `Advisor`
  
  `applyCommonInterceptorsFirst` 这个属性控制 是否应用 commonInterceptor
- `private final Set<String> targetSourcedBeans`
- `private final Set<Object> earlyProxyReferences` 
- `private final Map<Object, Class<?>> proxyTypes`
- `private final Map<Object, Boolean> advisedBeans`


<br>

还有很多重要的方法：

`isInfrastructureClass(beanClass) 和 shouldSkip(beanClass, beanName)` 这两个方法 是bean是否要被代理的重要判读依据

```java
// 如果是 Advice org.springframework.aop.Pointcut Advisor AopInfrastructureBean 的实现类，都是 aop的基础类，都不考虑 代理
protected boolean isInfrastructureClass(Class<?> beanClass) {
    boolean retVal = Advice.class.isAssignableFrom(beanClass) ||
            Pointcut.class.isAssignableFrom(beanClass) ||
            Advisor.class.isAssignableFrom(beanClass) ||
            AopInfrastructureBean.class.isAssignableFrom(beanClass);
    return retVal;
}

// 不是aop基础类的话，在判断是否需要 跳过，一般都有子类实现

// 比如说 AspectJAwareAdvisorAutoProxyCreator 就实现了 该方法，但他也是找一下是不是 AspectJPointcutAdvisor
// 这个也可以认为是 基础类，所以 还是默认处理所有类。。。
// 查了一下， AspectJPointcutAdvisor 是在解析 XML 中的aspectj的时候创建的 advisor 的类型
protected boolean shouldSkip(Class<?> beanClass, String beanName) {
    return false;
}
```

> ps: 暂时只有`AspectJAwareAdvisorAutoProxyCreator`实现了 shouldSkip 方法，其他都没有，直接返回false，也就是不跳过任何类

<br>

--------

`protected abstract Object[] getAdvicesAndAdvisorsForBean(Class<?> beanClass, String beanName, TargetSource customTargetSource)` 获取某个bean 的 Advice和Advisor

也是提供给子类的，`BeanNameAutoProxyCreator` 和 `AbstractAdvisorAutoProxyCreator` 实现了，他也只有这两个类，也就是提供了两种策略去匹配某个bean的advisor

<br>

先看看`BeanNameAutoProxyCreator` 根据BeanName筛选的 advisor：

```java

// 这就是 该类的所有代码了，就是可以设置 beanNames 属性，然后 匹配 beanName 如果匹配了 就返回 要代理，
// 它现在的实现只能 创建 commonInterceptors 代理。
public class BeanNameAutoProxyCreator extends AbstractAutoProxyCreator {

	@Nullable
	private List<String> beanNames;

	public void setBeanNames(String... beanNames) {
		Assert.notEmpty(beanNames, "'beanNames' must not be empty");
		this.beanNames = new ArrayList<>(beanNames.length);
		for (String mappedName : beanNames) {
			this.beanNames.add(StringUtils.trimWhitespace(mappedName));
		}
	}

	@Override
	@Nullable
	protected Object[] getAdvicesAndAdvisorsForBean(
			Class<?> beanClass, String beanName, @Nullable TargetSource targetSource) {

		if (this.beanNames != null) {
            // 遍历配置的每一个 mappedName 支持 xxx* *xxx 这种
			for (String mappedName : this.beanNames) {
                // 如果这是个 FactoryBean ，去掉前缀
				if (FactoryBean.class.isAssignableFrom(beanClass)) {
					if (!mappedName.startsWith(BeanFactory.FACTORY_BEAN_PREFIX)) {
						continue;
					}
					mappedName = mappedName.substring(BeanFactory.FACTORY_BEAN_PREFIX.length());
				}
                // 使用正则匹配
				if (isMatch(beanName, mappedName)) {
					return PROXY_WITHOUT_ADDITIONAL_INTERCEPTORS;
				}
				BeanFactory beanFactory = getBeanFactory();
				if (beanFactory != null) {
					String[] aliases = beanFactory.getAliases(beanName);
					for (String alias : aliases) {
						if (isMatch(alias, mappedName)) {
							return PROXY_WITHOUT_ADDITIONAL_INTERCEPTORS;
						}
					}
				}
			}
		}
		return DO_NOT_PROXY;
	}

    // 正则匹配
	protected boolean isMatch(String beanName, String mappedName) {
		return PatternMatchUtils.simpleMatch(mappedName, beanName);
	}

}
```

就是根据配置的beanNames，看要被代理的beanName 是否满足正则匹配的筛选条件，但是只能创建 commonInterceptor 的代理。

<br>

再看看`AbstractAdvisorAutoProxyCreator`及他的子类等：

```java
// AbstractAdvisorAutoProxyCreator
protected Object[] getAdvicesAndAdvisorsForBean(
        Class<?> beanClass, String beanName, @Nullable TargetSource targetSource) {

    List<Advisor> advisors = findEligibleAdvisors(beanClass, beanName);
    if (advisors.isEmpty()) {
        return DO_NOT_PROXY;
    }
    return advisors.toArray();
}

protected List<Advisor> findEligibleAdvisors(Class<?> beanClass, String beanName) {
    // 找到所有的 advisor
    List<Advisor> candidateAdvisors = findCandidateAdvisors();
    // 看看这些 advisor 是否 能应用在 该bean上面
    List<Advisor> eligibleAdvisors = findAdvisorsThatCanApply(candidateAdvisors, beanClass, beanName);
    //留给子类扩展的
    extendAdvisors(eligibleAdvisors);
    if (!eligibleAdvisors.isEmpty()) {
        eligibleAdvisors = sortAdvisors(eligibleAdvisors);
    }
    return eligibleAdvisors;
}

protected List<Advisor> findCandidateAdvisors() {
    // 这里托付给 advisorRetrievalHelper 来找，就是 扫描所有bean，找 Advisor 的实现类的对象
    return this.advisorRetrievalHelper.findAdvisorBeans();
}
```

大致思路就是 找到 所有 Advisor，然后 看看这些 Advisor 是否可apply在 该bean上。

<br>

`AbstractAdvisorAutoProxyCreator` 的子类 `AnnotationAwareAspectJAutoProxyCreator extends AspectJAwareAdvisorAutoProxyCreator` 也扩展了上面的几个方法：

```java
//AnnotationAwareAspectJAutoProxyCreator 类中的方法
@Override
protected List<Advisor> findCandidateAdvisors() {
    // super 从beanFactory 找 advisor 的子类的实现类
    List<Advisor> advisors = super.findCandidateAdvisors();
    if (this.aspectJAdvisorsBuilder != null) {
        // 他自己又委托给 aspectJAdvisorBuilder 找了一次
        // 这里找的 是 AspectJ 注解的，然后将这些注解 的@Before 等 转换为 Advisor
        advisors.addAll(this.aspectJAdvisorsBuilder.buildAspectJAdvisors());
    }
    return advisors;
}

    @Override
protected boolean isInfrastructureClass(Class<?> beanClass) {
    // 这里 再将 @AspectJ 注解的类 也认为是 基础类
    return (super.isInfrastructureClass(beanClass) ||
            (this.aspectJAdvisorFactory != null && this.aspectJAdvisorFactory.isAspect(beanClass)));
}

// AspectJAwareAdvisorAutoProxyCreator 类中的方法
// 如果 已经找到了 对这个 bean 的 advisor，那再加上个 ExposeInvocationInterceptor
// 如果没找到，也就不加了。
protected void extendAdvisors(List<Advisor> candidateAdvisors) {
    AspectJProxyUtils.makeAdvisorChainAspectJCapableIfNecessary(candidateAdvisors);
}

```

还有 `createProxy, SmartInstantiationAwareBeanPostProcessor的所有实现方法 等等` 都在这里。

<br> 

---------

最后终于对这个类，以及一些子类了解些了，那么再看这些类的功能：

- `AbstractAutoProxyCreator`: Spring 为Spring AOP 模块暴露的可扩展抽象类，也是 AOP 中最核心的抽象类。Nepxion Matrix 框架便是基于此类对AOP进行扩展和增强。
- `BeanNameAutoProxyCreator`: 根据指定名称创建代理对象（阿里大名鼎鼎的连接池框架druid也基于此类做了扩展）。通过设置 advisor，可以对指定的 beanName 进行代理。支持模糊匹配。
- `AbstractAdvisorAutoProxyCreator`: 功能比较强大，默认扫描所有Advisor的实现类。相对于根据Bean名称匹配，该类更加灵活。动态的匹配每一个类，判断是否可以被代理，并寻找合适的增强类，以及生成代理类。
- `DefaultAdvisorAutoProxyCreator`: AbstractAdvisorAutoProxyCreator的默认实现类。可以单独使用，在框架中使用AOP，尽量不要手动创建此对象。
- `AspectJAwareAdvisorAutoProxyCreator`: 支持了AspectJ注解，将@AspectJ注解的类中的@Before 等注解转换为 对应的Advisor，是Aspectj的实现方式，也是Spring Aop中最常用的实现方式，如果用注解方式，则用其子类AnnotationAwareAspectJAutoProxyCreator。
- `AnnotationAwareAspectJAutoProxyCreator`: 目前最常用的AOP使用方式。spring aop 开启注解方式之后，该类会扫描所有@Aspect()注释的类，生成对应的adviosr。目前SpringBoot框架中默认支持的方式，自动配置。
- `ProxyConfig` 声明了 配置的Proxy一些属性，比如说 proxyTargetClass, exposeProxy 等。各个creator 都需要继承它
- `AopInfrastructureBean` 就是一个标志性的接口，实现该接口表示 是 AOP的基础bean，在扫描创建代理过滤的时候，是要忽略的。`isInfrastructureClass`方法的一个判断就是 是否实现了这个接口。 一般都是 PostProcessor 和 Creator 实现该接口。


<br>

--------

### Advisor, Advice 与 Pointcut

- `org.springframework.aop.Advisor` 是spring提供的 用来整合aop切面数据的类。
- `org.aopalliance.aop.Advice` 是aop提供的真正处理 代理逻辑的类。
- `org.springframework.aop.Pointcut` spring提供的，将`ClassFilter, MethodMatcher`整合到一起的类，用于在筛选bean。 这里说的是这个Pointcut
- `org.aspectj.lang.annotation.Pointcut` 就是在 `@Aspect` 使用的`@Pointcut`，标记一个 Pointcut 切点。
- `org.aspectj.lang.reflect.Pointcut` aspectJ中的`@Pointcut` 在aop 运行时的表示。

一般的一个 `Advisor`必须要能够获取`Advice`，`PointcutAdvisor`还可以获取 Spring的`Pointcut`。`Advice`作为此次aop的处理逻辑，`Pointcut`作为筛选条件，那些bean要被这个advice代理。

<br>

**`Advisor`**

上类图：
![|center](/images/springboot-aop-classmap-advisor.jpg)

<br>

所有的都是`PointcutAdvisor`

分为三大块，`InstantiationModelAwarePointcutAdvisor, AbstractGenericPointcutAdvisor, 其他`。
- `InstantiationModelAwarePointcutAdvisor` 它有个唯一的实现，所有被`@Aspect`注解的类都会创建一个该类型的对象。
- `AbstractGenericPointcutAdvisor` Abs系列。这些可以自定义 `Advice, Pointcut`，我们可以随便使用，系统也提供了一些常用的实现。
  
  比如说想通过正则来筛选被代理对象，就可以使用`RegexpMethodPointcutAdvisor`，想通过methodName的就使用`NameMatchMethodPointcutAdvisor`。
  - `DefaultPointcutAdvisor` Advice 是 空，Pointcut 都返回true。构造方法可以传入这两个参数，最灵活，我们可以随便配置。
- `其他` 主要有`StaticMethodMatcherPointcutAdvisor`，
  - `StaticMethodMatcherPointcutAdvisor` 用来做基于静态方法的Advisor。使用的话直接实现 `MethodMatch`的`match`方法，其实是 `StaticMethodMatcherPointcut`的，也就是我们的筛选条件。Advice的话 是默认的 EMPTY_ADVICE。


<br>

**`Advice`**

上类图：
![|center](/images/springboot-aop-classmap-advice.png)

`org.aopalliance.aop.Advice`完整类名。是由AOP提供的该类，而且还提供了`Interceptor 和 MethodInterceptor`。

`Advice`是真正代理的逻辑所在的地方，所以类也多和相关业务相关。

- `AspectJ AOP` 相关业务。主要类有 `AspectJMethodBeforeAdvice, AspectJAfterReturningAdvice, AspectJAfterAdvice, AspectJAroundAdvice, ThrowingXXXAdvice`。涉及的主要的类就是`AbstractAspectJAdvice` 他们会针对特定的注解生成特定的Advice，在方法的执行过程中嵌入进去，并通过反射调用用户增加的逻辑。
- `事务` 相关业务。有`TransactionInterceptor`。
- `自定义Advice` 我们可以随便自定义Advice，使用自己的Advice。

<br>

与AspectJ业务相关的还有一个接口: `AspectJPrecedenceInformation` 主要提供了一些接口方法，返回一些信息，针对AspectJ相关的注解生成的Advice/Advisor， 能够方便的排序。

```java
public interface AspectJPrecedenceInformation extends Ordered {
	/**
	 * Return the name of the aspect (bean) in which the advice was declared.
	 */
	String getAspectName();

	/**
	 * Return the declaration order of the advice member within the aspect.
     * advice member的声明order
	 */
	int getDeclarationOrder();

	/**
	 * Return whether this is a before advice.
	 */
	boolean isBeforeAdvice();

	/**
	 * Return whether this is an after advice.
	 */
	boolean isAfterAdvice();
}

```

<br>

**`Pointcut`**

上类图：
![|center](/images/springboot-aop-classmap-pointcut.jpg)

<br>

`Pointcut` 就可以理解为筛选条件。通过`ClassFilter 和 MethodMatcher`

他也可以分为三大类：`StaticMethodMatcherPointcut, AnnotationMatchingPointcut, ExpressionPointcut`
- `StaticMethodMatcherPointcut` 根据方法筛选。具体通过实现`MethodMatcher`接口，通过他的`match`方法。他的`classFilter`默认就总返回true
- `AnnotationMatchingPointcut` 根据注解筛选。 构造方法的参数是Class Annotation 和 method Annotation。如果传了，就创建`AnnotationClassFilter, AnnotationMethodMatcher`。不传就是`TRUE`
  
  通过类图也可以看到`AnnotationMethodMatcher`也是`StaticMethodMatcher`的一个子类
- `ExpressionPointcut` 根据表达式筛选，就是针对AspectJ的`execute` 表达式，而且产生的 MethodFilter 和 ClassFilter 都是实际通过调用 aspect包中的类来完成筛选的。


<br>

-------

## 源码分析


### 自动装配-创建`AnnotationAwareAspectJAutoProxyCreator`


还是从`AopAutoConfiguration` 开始。

```java
@Configuration
@ConditionalOnClass({ EnableAspectJAutoProxy.class, Aspect.class, Advice.class,
		AnnotatedElement.class })
@ConditionalOnProperty(prefix = "spring.aop", name = "auto", havingValue = "true", matchIfMissing = true)
public class AopAutoConfiguration {

    // 如果不专门配置 会使用CglibAutoProxyConfiguration
    // 因为它上面的 matchIfMissing=true

	@Configuration
	@EnableAspectJAutoProxy(proxyTargetClass = false)
	@ConditionalOnProperty(prefix = "spring.aop", name = "proxy-target-class", havingValue = "false", matchIfMissing = false)
	public static class JdkDynamicAutoProxyConfiguration {
	}

	@Configuration
	@EnableAspectJAutoProxy(proxyTargetClass = true)
	@ConditionalOnProperty(prefix = "spring.aop", name = "proxy-target-class", havingValue = "true", matchIfMissing = true)
	public static class CglibAutoProxyConfiguration {
	}
}

@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Import(AspectJAutoProxyRegistrar.class)
// 该类还Import 了 AspectJAutoProxyRegistrar 他是一个 ImportRegistrar 注册了 AnnotationAwareAspectJAutoProxyCreator
public @interface EnableAspectJAutoProxy {

    // 是否针对java 中的interface 使用 cglib 代理方式
    // 默认false，interface 使用 jdk，class 使用 cglib
    // true 都是用 cglib
	boolean proxyTargetClass() default false;

	/**
	 * Indicate that the proxy should be exposed by the AOP framework as a {@code ThreadLocal}
	 * for retrieval via the {@link org.springframework.aop.framework.AopContext} class.
	 * Off by default, i.e. no guarantees that {@code AopContext} access will work.
	 * @since 4.3.1
     * 可以在启动类上通过加上该注解 设置 exposeProxy=true 之后可以通过AopContext 获取 代理对象。
	 */
	boolean exposeProxy() default false;
}
```

<br>

`AopAutoConfiguration`是AOP的自动装配类。根据配置选择不同的代理方式，默认选择支持 classProxy的 `CglibAutoProxyConfiguration`。 它又引入了注解`@EnableAspectJAutoProxy`， 该注解引入了ImportRegistrar -- `AspectJAutoProxyRegistrar`，它最终注册了bean `AnnotationAwareAspectJAutoProxyCreator`。

> `@EnableAspectJAutoProxy`也可以在主类上增加注解配置代理的方式和设置是否 exposeProxy。

<br>

---------

**`定义 AnnotationAwareAspectJAutoProxyCreator`**

看`AspectJAutoProxyRegistrar.registerBeanDefinitions`

```java

public void registerBeanDefinitions(
        AnnotationMetadata importingClassMetadata, BeanDefinitionRegistry registry) {

    // 最后调用了 AopConfigUtils.registerOrEscalateApcAsRequired
    AopConfigUtils.registerAspectJAnnotationAutoProxyCreatorIfNecessary(registry);

    AnnotationAttributes enableAspectJAutoProxy =
            AnnotationConfigUtils.attributesFor(importingClassMetadata, EnableAspectJAutoProxy.class);
    if (enableAspectJAutoProxy != null) {
        // 设置配置的属性，这些属性最终会保存在 创建好的该对象的属性中
        if (enableAspectJAutoProxy.getBoolean("proxyTargetClass")) {
            AopConfigUtils.forceAutoProxyCreatorToUseClassProxying(registry);
        }
        if (enableAspectJAutoProxy.getBoolean("exposeProxy")) {
            AopConfigUtils.forceAutoProxyCreatorToExposeProxy(registry);
        }
    }
}

private static BeanDefinition registerOrEscalateApcAsRequired(Class<?> cls, BeanDefinitionRegistry registry,
        @Nullable Object source) {

    Assert.notNull(registry, "BeanDefinitionRegistry must not be null");

    // 不知道干嘛了
    if (registry.containsBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME)) {
        BeanDefinition apcDefinition = registry.getBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME);
        if (!cls.getName().equals(apcDefinition.getBeanClassName())) {
            int currentPriority = findPriorityForClass(apcDefinition.getBeanClassName());
            int requiredPriority = findPriorityForClass(cls);
            if (currentPriority < requiredPriority) {
                apcDefinition.setBeanClassName(cls.getName());
            }
        }
        return null;
    }

    RootBeanDefinition beanDefinition = new RootBeanDefinition(cls);
    // source = null
    beanDefinition.setSource(source);
    // 最高优先级
    beanDefinition.getPropertyValues().add("order", Ordered.HIGHEST_PRECEDENCE);
    // ROLE_INFRASTRUCTURE 基础组件
    beanDefinition.setRole(BeanDefinition.ROLE_INFRASTRUCTURE);
    registry.registerBeanDefinition(AUTO_PROXY_CREATOR_BEAN_NAME, beanDefinition);
    return beanDefinition;
}

```

<br>

**`创建 AnnotationAwareAspectJAutoProxyCreator`**

就是createBean的流程，将beanDefinition 中定义的配置设置进去，比如常见的`proxyTargetClass, exposeProxy`等，都在`ProxyConfig`中。

创建好的`AnnotationAwareAspectJAutoProxyCreator`除了有之前设置好的属性外，还有几个成员对象。

![|center](/images/springboot-aop-classmap-aaaasimple.jpg)


1. `BeanFactoryAdvisorRetrievalHelperAdapter` 辅助从BeanFactory中找 `Advisor`

`AbstractAdvisorAutoProxyCreator` 重写了 `setBeanFactory`方法，并调用了`initBeanFactory` 方法，在这里面创建了 `BeanFactoryAdvisorRetrievalHelperAdapter`
```java
// AbstractAdvisorAutoProxyCreator
protected void initBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    this.advisorRetrievalHelper = new BeanFactoryAdvisorRetrievalHelperAdapter(beanFactory);
}

// 将 findCandidate的任务委托给 advisorRetrievalHelper，
// 实际就是扫描所有的bean，找到 Advisor 类型的
protected List<Advisor> findCandidateAdvisors() {
    Assert.state(this.advisorRetrievalHelper != null, "No BeanFactoryAdvisorRetrievalHelper available");
    return this.advisorRetrievalHelper.findAdvisorBeans();
}
```

<br>

2. `AspectJAdvisorFactory & BeanFactoryAspectJAdvisorsBuilder` 合作 解析 AspectJ 注解的类为 Advisor

`AnnotationAwareAspectJAutoProxyCreator`重写了`initBeanFactory`，又创建了两个对象，方便自己 找 AspectJ这样的Advisor

```java
// AnnotationAwareAspectJAutoProxyCreator
@Override
protected void initBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    // 调用父类
    super.initBeanFactory(beanFactory);

    // 创建 factory 和 builder，俩人合作 找AspectJ 注解，然后变成 Advisor
    if (this.aspectJAdvisorFactory == null) {
        this.aspectJAdvisorFactory = new ReflectiveAspectJAdvisorFactory(beanFactory);
    }
    this.aspectJAdvisorsBuilder =
            new BeanFactoryAspectJAdvisorsBuilderAdapter(beanFactory, this.aspectJAdvisorFactory);
}

@Override
protected List<Advisor> findCandidateAdvisors() {
    // Add all the Spring advisors found according to superclass rules.
    // 调用父类 获取 advisor，也就是 扫描 Advisor
    List<Advisor> advisors = super.findCandidateAdvisors();
    // Build Advisors for all AspectJ aspects in the bean factory.
    if (this.aspectJAdvisorsBuilder != null) {
        // 子类获取Advisor 也就是 扫面 AspectJ 并生成 Advisor
        advisors.addAll(this.aspectJAdvisorsBuilder.buildAspectJAdvisors());
    }
    return advisors;
}
```

<br>

--------

### 找Advisor

找Advisor是父类 `AbstractAutoProxyCreator.getAdvicesAndAdvisorsForBean`提供的，但是具体的实现完全是子类完成的。

前面也说过，对于他的两大子类来说，
- `BeanNameAutoProxyCreator`是比较简单的，如何BeanName 正则匹配设置好的mappedName，就会设置代理，但是 **只会设置统一的代理**。
- `AbstractAdvisorAutoProxyCreator` 会先找出所有的Advisor，然后再根据当前bean去匹配Advisor，看是否这个Advisor匹配成功，成功的话就设置代理，没有一个成功的就不设置代理。
  
  出现多个匹配的Advisor，就会涉及到排序的问题，因为Advisor由spring管理，所有可以根据Order来排序。
  - `AnnotationAwareAspectJAutoProxyCreator` AspectJ 系的，在扫描所有Advisor的时候，增加了扫描`@AspectJ`注解，并将其变成`Advisor`。
    
    因为`@Aspect`注解的bean扫描出来之后的Advisor的order都是一样的，所以又专门提供了`AspectJPrecedenceInformation`接口，保存一些被`@Aspect`注解的生成的Advisor的元数据，比如说标识是 before 还是 after，方法的声明顺序等等。

<br>

---------

首先看看扫描`Advisor`的过程，具体是由`AbstractAdvisorAutoProxyCreator`中的`BeanFactoryAdvisorRetrievalHelper advisorRetrievalHelper`代理完成的。

```java
/**
    * Find all eligible Advisor beans in the current bean factory,
    * ignoring FactoryBeans and excluding beans that are currently in creation.
    * eligible 合格的
    * 找所有 合格的advisor从Bean factory中
    * 忽略FactoryBean，(因为代码里面只扫描了 Advisor类型的bean，没有扫描FactoryBean的逻辑)，和正在创建的Bean
    * 正在创建的Bean 是要被代理的对象，当然不能又作为代理了。
    */
public List<Advisor> findAdvisorBeans() {
    // 先从cache 里拿
    String[] advisorNames = this.cachedAdvisorBeanNames;
    if (advisorNames == null) {
        // Do not initialize FactoryBeans here: We need to leave all regular beans
        // uninitialized to let the auto-proxy creator apply to them!
        advisorNames = BeanFactoryUtils.beanNamesForTypeIncludingAncestors(
                this.beanFactory, Advisor.class, true, false);
        this.cachedAdvisorBeanNames = advisorNames;
    }
    if (advisorNames.length == 0) {
        return new ArrayList<>();
    }

    List<Advisor> advisors = new ArrayList<>();
    for (String name : advisorNames) {
        // 是否是 合格的Advisor
        // 具体合格与否 这里又回调到了 AbstractAdvisorAutoProxyCreator.isEligibleAdvisorBean , 恒 true
        if (isEligibleBean(name)) {
            // 正在创建的bean  忽略
            if (this.beanFactory.isCurrentlyInCreation(name)) {
                if (logger.isDebugEnabled()) {
                    logger.debug("Skipping currently created advisor '" + name + "'");
                }
            }
            else {
                try {
                    // 真正的getBean 并添加到 advisor中
                    advisors.add(this.beanFactory.getBean(name, Advisor.class));
                }
                catch (BeanCreationException ex) {
                    Throwable rootCause = ex.getMostSpecificCause();
                    if (rootCause instanceof BeanCurrentlyInCreationException) {
                        BeanCreationException bce = (BeanCreationException) rootCause;
                        String bceBeanName = bce.getBeanName();
                        if (bceBeanName != null && this.beanFactory.isCurrentlyInCreation(bceBeanName)) {
                            // Ignore: indicates a reference back to the bean we're trying to advise.
                            // We want to find advisors other than the currently created bean itself.
                            continue;
                        }
                    }
                    throw ex;
                }
            }
        }
    }
    return advisors;
}

```

<br>

再看看 `AnnotationAwareAspectJAutoProxyCreator`扫描`@AspectJ`转换为`Advisor`的过程。

它将扫描`AspectJ`和创建对应`Advisor`的过程委托给了 `BeanFactoryAspectJAdvisorsBuilder aspectJAdvisorsBuilder`

```java
/**
    * Look for AspectJ-annotated aspect beans in the current bean factory,
    * and return to a list of Spring AOP Advisors representing them.
    * <p>Creates a Spring Advisor for each AspectJ advice method.</p>
    */
public List<Advisor> buildAspectJAdvisors() {
    List<String> aspectNames = this.aspectBeanNames;

    // 如果是第一次扫描，就去扫描所有的bean，之后直接拿缓存就行了
    if (aspectNames == null) {
        synchronized (this) {
            aspectNames = this.aspectBeanNames;
            if (aspectNames == null) {
                List<Advisor> advisors = new ArrayList<>();
                aspectNames = new ArrayList<>();
                // 拿到所有的 bean，一个个循环看 
                String[] beanNames = BeanFactoryUtils.beanNamesForTypeIncludingAncestors(
                        this.beanFactory, Object.class, true, false);
                for (String beanName : beanNames) {
                    // 是否合格，满足基本要求， 恒 true
                    if (!isEligibleBean(beanName)) {
                        continue;
                    }
                    // We must be careful not to instantiate beans eagerly as in this case they
                    // would be cached by the Spring container but would not have been weaved.
                    Class<?> beanType = this.beanFactory.getType(beanName);
                    if (beanType == null) {
                        continue;
                    }
                    // 交给advisorFactory判断是否又@AspectJ 注解，有继续
                    if (this.advisorFactory.isAspect(beanType)) {
                        aspectNames.add(beanName);
                        // 拿到 Aspect 元数据，比如AspectJ 注解的真正的class，已经 AspectJ 属性中的意思
                        AspectMetadata amd = new AspectMetadata(beanType, beanName);

                        // PerClauseKind.SINGLETON 是AspectJ 的默认值
                        if (amd.getAjType().getPerClause().getKind() == PerClauseKind.SINGLETON) {
                            // 初始化 创建 将AsepctJ 数据转换为 Advisor的 InstantiationModelAwarePointcutAdvisorImpl 的工厂。
                            MetadataAwareAspectInstanceFactory factory =
                                    new BeanFactoryAspectInstanceFactory(this.beanFactory, beanName);
                            // 交给 advisorFactory，扫描bean中的所有方法，真正创建 Advisor
                            List<Advisor> classAdvisors = this.advisorFactory.getAdvisors(factory);
                            if (this.beanFactory.isSingleton(beanName)) {
                                this.advisorsCache.put(beanName, classAdvisors);
                            }
                            else {
                                this.aspectFactoryCache.put(beanName, factory);
                            }
                            advisors.addAll(classAdvisors);
                        }
                        else {
                            // Per target or per this.
                            if (this.beanFactory.isSingleton(beanName)) {
                                throw new IllegalArgumentException("Bean with name '" + beanName +
                                        "' is a singleton, but aspect instantiation model is not singleton");
                            }
                            // 不同的AspectJ(可以通过value指定,默认SINGLETON，也就是上面那个) 类型交给不同的工厂去处理，具体看 PerClauseKind 和 MetadataAwareAspectInstanceFactory
                            MetadataAwareAspectInstanceFactory factory =
                                    new PrototypeAspectInstanceFactory(this.beanFactory, beanName);
                            this.aspectFactoryCache.put(beanName, factory);
                            advisors.addAll(this.advisorFactory.getAdvisors(factory));
                        }
                    }
                }
                this.aspectBeanNames = aspectNames;
                return advisors;
            }
        }
    }

    // 如果没找到 就直接返回
    if (aspectNames.isEmpty()) {
        return Collections.emptyList();
    }

    // 这是上面保存到了缓存里面，之后就直接走这里从缓存拿了
    List<Advisor> advisors = new ArrayList<>();
    for (String aspectName : aspectNames) {
        List<Advisor> cachedAdvisors = this.advisorsCache.get(aspectName);
        if (cachedAdvisors != null) {
            advisors.addAll(cachedAdvisors);
        }
        else {
            MetadataAwareAspectInstanceFactory factory = this.aspectFactoryCache.get(aspectName);
            advisors.addAll(this.advisorFactory.getAdvisors(factory));
        }
    }
    return advisors;
}

```

<br>

下面看看 `ReflectiveAspectJAdvisorFactory.getAdvisors`具体扫描 `@AspectJ` 创建 Advisor 的过程。

```java
// 根据 AspectJ 注解的类，构建 Advisor
public List<Advisor> getAdvisors(MetadataAwareAspectInstanceFactory aspectInstanceFactory) {
    Class<?> aspectClass = aspectInstanceFactory.getAspectMetadata().getAspectClass();
    String aspectName = aspectInstanceFactory.getAspectMetadata().getAspectName();
    validate(aspectClass);

    // We need to wrap the MetadataAwareAspectInstanceFactory with a decorator
    // so that it will only instantiate once.
    // 将 AspectInstanceFactory 包装一层，变成单例 可复用的
    MetadataAwareAspectInstanceFactory lazySingletonAspectInstanceFactory =
            new LazySingletonAspectInstanceFactoryDecorator(aspectInstanceFactory);

    List<Advisor> advisors = new ArrayList<>();
    // 没有 org.aspectj.lang.annotation.Pointcut 注解的方法 都会被拿出来
    // 然后 根据 Around Before After AfterReturning AfterThrowing 的顺序排序，最后再根据 方法名 排序
    // 具体排序的Comparator 可以看 ReflectiveAspectJAdvisorFactory.METHOD_COMPARATOR
    for (Method method : getAdvisorMethods(aspectClass)) {
        Advisor advisor = getAdvisor(method, lazySingletonAspectInstanceFactory, advisors.size(), aspectName);
        // 有被正确注解的方法 会产生 Advisor，没有注解的 会返回 默认的额EMPTY_ADVICE 也就是null
        if (advisor != null) {
            advisors.add(advisor);
        }
    }

    // If it's a per target aspect, emit the dummy instantiating aspect.
    if (!advisors.isEmpty() && lazySingletonAspectInstanceFactory.getAspectMetadata().isLazilyInstantiated()) {
        Advisor instantiationAdvisor = new SyntheticInstantiationAdvisor(lazySingletonAspectInstanceFactory);
        advisors.add(0, instantiationAdvisor);
    }

    // Find introduction fields.
    // 找完方法了，在找 field，用的不多，具体不分析了。
    for (Field field : aspectClass.getDeclaredFields()) {
        Advisor advisor = getDeclareParentsAdvisor(field);
        if (advisor != null) {
            advisors.add(advisor);
        }
    }

    return advisors;
}

// 根据方法声明 getAdvisor
public Advisor getAdvisor(Method candidateAdviceMethod, MetadataAwareAspectInstanceFactory aspectInstanceFactory,
        int declarationOrderInAspect, String aspectName) {

    validate(aspectInstanceFactory.getAspectMetadata().getAspectClass());

    // AspectJExpressionPointcut 这个类还是spring 的 Pointcut
    // 用来做筛选条件的，筛选 AspectJ 中的筛选条件
    AspectJExpressionPointcut expressionPointcut = getPointcut(
            candidateAdviceMethod, aspectInstanceFactory.getAspectMetadata().getAspectClass());
    if (expressionPointcut == null) {
        return null;
    }

    // 和 Pointcut 的创建差不多，创建了Advice 就是把 class, method, parameterTypes, pointcut, aspectInstanceFactory 保存起来，
    // 然后是AspectJ 注解的，Advice 还需要注意下排序的问题，还有一些参数绑定 等等。
    return new InstantiationModelAwarePointcutAdvisorImpl(expressionPointcut, candidateAdviceMethod,
            this, aspectInstanceFactory, declarationOrderInAspect, aspectName);
}

// 根据声明的方法 获取 AspectJExpressionPointcut，就保存了 注解后的值。
@Nullable
private AspectJExpressionPointcut getPointcut(Method candidateAdviceMethod, Class<?> candidateAspectClass) {
    AspectJAnnotation<?> aspectJAnnotation =
            AbstractAspectJAdvisorFactory.findAspectJAnnotationOnMethod(candidateAdviceMethod);
    if (aspectJAnnotation == null) {
        return null;
    }

    AspectJExpressionPointcut ajexp =
            new AspectJExpressionPointcut(candidateAspectClass, new String[0], new Class<?>[0]);
    // 这里只保存了 表达式，因为 Pointcut 是筛选的么，所以 只需要根据表达式来筛选就行了
    ajexp.setExpression(aspectJAnnotation.getPointcutExpression());
    if (this.beanFactory != null) {
        ajexp.setBeanFactory(this.beanFactory);
    }
    return ajexp;
}
```


<br>

最后看看Advisor是否适合当前bean 的过程，具体是`AbstractAdvisorAutoProxyCreator.findAdvisorsThatCanApply`，实际执行的是 `AopUtils.findAdvisorsThatCanApply(candidateAdvisors, beanClass)`:

```java
// 这里对于 IntroductionAdvisor 的处理是不同的，是单独处理的 
public static List<Advisor> findAdvisorsThatCanApply(List<Advisor> candidateAdvisors, Class<?> clazz) {
    if (candidateAdvisors.isEmpty()) {
        return candidateAdvisors;
    }
    List<Advisor> eligibleAdvisors = new ArrayList<>();
    // 先判断是否 有 IntroductionAdvisor 可以使用
    for (Advisor candidate : candidateAdvisors) {
        if (candidate instanceof IntroductionAdvisor && canApply(candidate, clazz)) {
            eligibleAdvisors.add(candidate);
        }
    }
    boolean hasIntroductions = !eligibleAdvisors.isEmpty();
    // 在判断 非 IntroductionAdvisor。 一般的话 都是 PointcutAdvisor
    for (Advisor candidate : candidateAdvisors) {
        if (candidate instanceof IntroductionAdvisor) {
            // already processed
            continue;
        }
        if (canApply(candidate, clazz, hasIntroductions)) {
            eligibleAdvisors.add(candidate);
        }
    }
    return eligibleAdvisors;
}


// 一般的话  非 IntroductionAdvisor的，都是 PointcutAdvisor，所以直接看 PointcutAdvisor 是怎么判断的
public static boolean canApply(Pointcut pc, Class<?> targetClass, boolean hasIntroductions) {
    Assert.notNull(pc, "Pointcut must not be null");

    // 如果 ClassFilter 不满足 直接拒绝不行
    if (!pc.getClassFilter().matches(targetClass)) {
        return false;
    }

    // 如果MethodMatcher 是默认的，那就直接返回true 匹配上了
    MethodMatcher methodMatcher = pc.getMethodMatcher();
    if (methodMatcher == MethodMatcher.TRUE) {
        // No need to iterate the methods if we're matching any method anyway...
        return true;
    }

    // 判断是否是一个 根据 Introduction 简化  IntroductionAwareMethodMatcher
    IntroductionAwareMethodMatcher introductionAwareMethodMatcher = null;
    if (methodMatcher instanceof IntroductionAwareMethodMatcher) {
        introductionAwareMethodMatcher = (IntroductionAwareMethodMatcher) methodMatcher;
    }

    Set<Class<?>> classes = new LinkedHashSet<>();
    // 拿到所有的类 和 方法
    if (!Proxy.isProxyClass(targetClass)) {
        classes.add(ClassUtils.getUserClass(targetClass));
    }
    classes.addAll(ClassUtils.getAllInterfacesForClassAsSet(targetClass));

    for (Class<?> clazz : classes) {
        Method[] methods = ReflectionUtils.getAllDeclaredMethods(clazz);
        for (Method method : methods) {
            if (introductionAwareMethodMatcher != null ?
                    // AspectJExpressionPointcut hasIntroductions = true的话，经过简单的判断验证，就会直接返回了，具体逻辑细节 也不清楚，
                    introductionAwareMethodMatcher.matches(method, targetClass, hasIntroductions) :
                    // 普通的话，直接 看是否 match
                    methodMatcher.matches(method, targetClass)) {
                return true;
            }
        }
    }

    return false;
}

```

<br>

---------

到这里 整个准备工作就完成了。最后还有几个小点要说：

**优先级问题**：

`AspectJPrecedenceInformation` 接口是专门针对于基于`@AspectJ`注解中，产生的`Advisor, Advice`无法判断优先级的问题的。

`Advisor`的排序是先根据自身的Order，如果没有设置Order，就从`Advice`中拿，如果还没有 就是最低：

```java
// AbstractPointcutAdvisor
@Override
public int getOrder() {
    if (this.order != null) {
        return this.order;
    }
    Advice advice = getAdvice();
    if (advice instanceof Ordered) {
        return ((Ordered) advice).getOrder();
    }
    return Ordered.LOWEST_PRECEDENCE;
}
```

<br>

`Advice`的排序也是根据Order的，但是对于AspectJ注解产生的Advice，他们的Order都是一样的，所以通过`AspectJPrecedenceInformation` 来保存元数据信息，并根据 `@Arount,@Before, @After, ..`注解的顺序先排序，再根据方法的名字再排序，最后的结果作为advice 的顺序。具体可以看 `ReflectiveAspectJAdvisorFactory.METHOD_COMPARATOR`

<br>

**AspectJ 再单独说明**

本源码分析流程就是以`@AspectJ`为例跑的。另外也比较特殊，可以专门再说一下。

- `Advisor` 是 `class InstantiationModelAwarePointcutAdvisorImpl implements InstantiationModelAwarePointcutAdvisor, AspectJPrecedenceInformation, Serializable`
- `Advice` 是 `public abstract class AbstractAspectJAdvice implements Advice, AspectJPrecedenceInformation, Serializable` 它具体的实现类有 `AspectJAfterAdvice`等
- `Pointcut` 是 `public class AspectJExpressionPointcut extends AbstractExpressionPointcut implements ClassFilter, IntroductionAwareMethodMatcher, BeanFactoryAware`。 他的父类 `AbstractExpressionPointcut` 就是多定义了 几个属性 `expression, location`等，具体逻辑 还是在这个类中
  
  `AspectJExpressionPointcut` 中的ClassFilter 和 MethodMatcher 都是 根据 expression 也就是 `@Before`类似这种注解的value来生成的。 具体某个类到底通不通过 filter，matches 其实是交给 AspectJ 处理的。包括 "@annotation "这种express

<br>

```java
@Aspect
@Component
public class LogableAspect2 {

    @Pointcut("@annotation(com.aop.annotation.Logable)")
    public void aspect() {
    }

    @Around("aspect()")
    public Object doAround(ProceedingJoinPoint point) throws Throwable {

        System.out.println("doAround before...");

        Object returnValue =  point.proceed(point.getArgs());

        System.out.println("doAround after...");
        return returnValue;
    }
}
```

<br>

**其他接口**

上文还有一些接口类没说到，但是也挺重要的，虽然用的不多，这里再说一下：

- `AspectJPrecedenceInformation` AspectJ 的其他基本信息，主要用于排序
- `IntroductionAdvisor` Advisor 的另一类，一般都是 `PointcutAdvisor`。 在判断Advisor 是否 `AopUtils.canApply` 的时候，会优先处理`IntroductionAdvisor`，而且`PointcutAdvisor`是否canApply，还会受到`IntroductionAdvisor`结果的影响。但是它用的并不多，自己也没有细研究。
  - `IntroductionAwareMethodMatcher` 如果想要影响 `PointcutAdvisor`，需要配合该类使用，只有`PointcutAdvisor`中的`Pointcut`是该类型的，才有可能收到影响，因为是该类型的，才在他的`MethodMatcher.matches`中加上 `IntroductionAdvisor` canApply的结果。
- **还有各种Spring提供的Advisor(`正则Advisor，NameMatcherAdvisor，DefaultAdvisor`)，提供的ProxyCreator(`AbstractAdvisorProxyCreator的子类`)，提供好的Pointcut(`JDK正则Pointcut，NameMatchPointcut等`)**
- `AdvisorAdapterRegistry` 可以保证，注入的advisor 可以是任何类型，只要我们再自定义个 Adapter 去包装下就行了。实际使用的是`DefaultAdvisorAdapterRegistry`


<br>

---------

### 创建与执行代理-Proxy

在`AbstractAutoProxyCreator.wrapIfNecessary`中，获取了`Advisor`，并创建了代理。

`AnnotationAwareAspectJAutoProxyCreator`实现类会添加一个通用的Advisor`ExposeInvocationInterceptor`，作用是在执行的时候将当前的`MethodInvocation`保存在`ThreadLocal`中。具体细节就不看了。。

真正创建代理的方法是拿到 `Object[] specificInterceptors`，也就是通常使用的`Advisor`数组后，执行的:

```java
// AbstractAutoProxyCreator.wrapIfNecessary
Object proxy = createProxy(
	bean.getClass(), beanName, specificInterceptors, new SingletonTargetSource(bean));
```

<br>

下面仔细分析下流程：

```java
protected Object createProxy(Class<?> beanClass, @Nullable String beanName,
        @Nullable Object[] specificInterceptors, TargetSource targetSource) {

    if (this.beanFactory instanceof ConfigurableListableBeanFactory) {
        // 在他的 BeanDefinition 中 增加 属性  originTargetClass，指向原来的 Class
        AutoProxyUtils.exposeTargetClass((ConfigurableListableBeanFactory) this.beanFactory, beanName, beanClass);
    }

    ProxyFactory proxyFactory = new ProxyFactory();
    // 将基本信息 copy，包括 创建 proxy的配置信息和 targetClass
    proxyFactory.copyFrom(this);

    // 如果不支持 classProxy的话，判断要代理的可以是不是 class，
    //      是的话 把proxyTargetClass设为true
    //      不是的话，找出来要被代理的interface
    if (!proxyFactory.isProxyTargetClass()) {
        if (shouldProxyTargetClass(beanClass, beanName)) {
            proxyFactory.setProxyTargetClass(true);
        }
        else {
            evaluateProxyInterfaces(beanClass, proxyFactory);
        }
    }
    // 增加 commonInterceptor，将 specificInterceptors 转换为 Advisor
    Advisor[] advisors = buildAdvisors(beanName, specificInterceptors);
    proxyFactory.addAdvisors(advisors);
    proxyFactory.setTargetSource(targetSource);
    // AbsAutoProxyCreator 留给子类的，但是子类 啥也没干
    customizeProxyFactory(proxyFactory);

    // 封锁配置，不能改了
    proxyFactory.setFrozen(this.freezeProxy);
    if (advisorsPreFiltered()) {
        proxyFactory.setPreFiltered(true);
    }

    // 最后根据这个新创建的 ProxyFactory，已经我们的配置，创建 真正的代理
    return proxyFactory.getProxy(getProxyClassLoader());
}
```

<br>

具体看看怎么 buildAdvisors:

```java
protected Advisor[] buildAdvisors(@Nullable String beanName, @Nullable Object[] specificInterceptors) {
    // 就是看看 AbstractAutoProxyCreator有没有设置好的 interceptorNames
    //  有的话，将他们getBean，获取实例返回，并且 还会使用 advisorAdapterRegistry，看是否需要包装。
    Advisor[] commonInterceptors = resolveInterceptorNames();

    // 把commonIntercetos 加入到 advisor 队列中，根据 applyCommonInterceptorsFirst 属性，看是加在前面还是后面
    List<Object> allInterceptors = new ArrayList<>();
    if (specificInterceptors != null) {
        allInterceptors.addAll(Arrays.asList(specificInterceptors));
        if (commonInterceptors.length > 0) {
            if (this.applyCommonInterceptorsFirst) {
                allInterceptors.addAll(0, Arrays.asList(commonInterceptors));
            }
            else {
                allInterceptors.addAll(Arrays.asList(commonInterceptors));
            }
        }
    }

    Advisor[] advisors = new Advisor[allInterceptors.size()];
    for (int i = 0; i < allInterceptors.size(); i++) {
        // 看看有没有 不是Advisor 类型的，给包装下，都变成Advisor
        advisors[i] = this.advisorAdapterRegistry.wrap(allInterceptors.get(i));
    }
    return advisors;
}

// advisorAdapterRegistry 是在 AbstractAutoProxyCreator创建的时候就 实例化好的。是 DefaultAdvisorAdapterRegistry
// 是 AdvisorAdapterRegistry 类型的
// 他比较简单，看一下就行
public class DefaultAdvisorAdapterRegistry implements AdvisorAdapterRegistry, Serializable {

	private final List<AdvisorAdapter> adapters = new ArrayList<>(3);

	public DefaultAdvisorAdapterRegistry() {
		registerAdvisorAdapter(new MethodBeforeAdviceAdapter());
		registerAdvisorAdapter(new AfterReturningAdviceAdapter());
		registerAdvisorAdapter(new ThrowsAdviceAdapter());
	}

    // 也就是说 它支持 Advisor 和 Advise 两种类型
    //      Advisor 会直接返回
    //      Advice 如果是 MethodInterceptor 就包装为 DefaultPointcutAdvisor，如果是其他类型的 会交给Adapter 处理
	@Override
	public Advisor wrap(Object adviceObject) throws UnknownAdviceTypeException {
		if (adviceObject instanceof Advisor) {
			return (Advisor) adviceObject;
		}
		if (!(adviceObject instanceof Advice)) {
			throw new UnknownAdviceTypeException(adviceObject);
		}
		Advice advice = (Advice) adviceObject;
		if (advice instanceof MethodInterceptor) {
			// So well-known it doesn't even need an adapter.
			return new DefaultPointcutAdvisor(advice);
		}
		for (AdvisorAdapter adapter : this.adapters) {
			// Check that it is supported.
			if (adapter.supportsAdvice(advice)) {
				return new DefaultPointcutAdvisor(advice);
			}
		}
		throw new UnknownAdviceTypeException(advice);
	}

    ...
}

```


<br>

ProxyFactory 的 `proxyFactory.getProxy(getProxyClassLoader());` 具体是怎么创建的：

```java

// 先创建代理类，在获取代理对象
public Object getProxy(@Nullable ClassLoader classLoader) {
    return createAopProxy().getProxy(classLoader);
}

// 先拿到 创建代理类的代理工厂 在用工厂 创建代理类
protected final synchronized AopProxy createAopProxy() {
    if (!this.active) {
        activate();
    }
    // 拿到的是默认的 AopProxyFactory -- DefaultAopProxyFactory
    return getAopProxyFactory().createAopProxy(this);
}

// DefaultAopProxyFactory 怎么创建代理类的
public class DefaultAopProxyFactory implements AopProxyFactory, Serializable {

    // 根据配置和实际被代理的 class 选择合适的(JDK or cglib)代理方式
    // 内部具体 就是 根据 Advisor 和 config，设置 cglib  or  jdk 代理的参数，然后 返回就是了
	@Override
	public AopProxy createAopProxy(AdvisedSupport config) throws AopConfigException {
		if (config.isOptimize() || config.isProxyTargetClass() || hasNoUserSuppliedProxyInterfaces(config)) {
			Class<?> targetClass = config.getTargetClass();
			if (targetClass == null) {
				throw new AopConfigException("TargetSource cannot determine target class: " +
						"Either an interface or a target is required for proxy creation.");
			}
			if (targetClass.isInterface() || Proxy.isProxyClass(targetClass)) {
				return new JdkDynamicAopProxy(config);
			}
			return new ObjenesisCglibAopProxy(config);
		}
		else {
			return new JdkDynamicAopProxy(config);
		}
	}

    ...
}

// 这里 AopProxy 就创建完了，具体是 CglibAopProxy 还是 JdkDynamicAopProxy 就确定了，而getProxy 真的创建 代理，就是 调用相关接口就是了，具体可以看那两个类

```



<br>

---------

## 说在最后

AspectJ是AOP的一种实现方式，而且拆分的特别细，采用的`execute` 等这一套东西。

SpringAOP是Spring中非常核心的一个东西，就像Context或者BeanFactory一样，是spring的构成基础。

SpringAOP提供了一套非常完整而且方便灵活的体系，通过`Advice`定义代理的逻辑，`Pointcut`定义代理的目标扫描对象，并用`Advisor`将这两个灵活组合，可以任意搞代理。

ApsectJ和execute 中的一套东西，包括`@Before @After`等等，SpringAOP为了兼容AspectJ 专门提供了一套Advice、Pointcut、Advisor来满足适配这些。

其实以后为了方便，完全不需要用AspectJ这一套扫描方案，明明自定义的Pointcut和Advice才是最方便灵活的。