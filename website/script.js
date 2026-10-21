const header = document.querySelector(".site-header")
const menuToggle = document.querySelector(".menu-toggle")
const navigation = document.querySelector(".main-nav")
const navLinks = [...document.querySelectorAll('.main-nav a[href^="#"]')]

function updateHeader() {
  header?.classList.toggle("scrolled", window.scrollY > 18)
}

menuToggle?.addEventListener("click", () => {
  const isOpen = navigation?.classList.toggle("open") ?? false
  menuToggle.setAttribute("aria-expanded", String(isOpen))
})

navLinks.forEach((link) => {
  link.addEventListener("click", () => {
    navigation?.classList.remove("open")
    menuToggle?.setAttribute("aria-expanded", "false")
  })
})

const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible")
        revealObserver.unobserve(entry.target)
      }
    })
  },
  { threshold: 0.12 }
)

document.querySelectorAll(".reveal").forEach((element) => revealObserver.observe(element))

const sectionObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return
      navLinks.forEach((link) => {
        link.classList.toggle("active", link.getAttribute("href") === `#${entry.target.id}`)
      })
    })
  },
  { rootMargin: "-35% 0px -55%", threshold: 0 }
)

document.querySelectorAll("main section[id]").forEach((section) => sectionObserver.observe(section))

// Drop a matching image into public/screenshots and the placeholder is replaced automatically.
document.querySelectorAll(".product-shot[data-src]").forEach((frame) => {
  const src = frame.dataset.src
  if (!src) return

  const image = new Image()
  image.alt = frame.querySelector("p, b")?.textContent?.trim() || "Shotly product screenshot"
  image.addEventListener("load", () => {
    frame.classList.add("has-image")
    frame.appendChild(image)
  })
  image.src = src
})

document.getElementById("current-year").textContent = new Date().getFullYear()

const coffeeModal = document.getElementById("coffee-modal")
const coffeeForm = document.getElementById("coffee-form")
const coffeeFormView = coffeeModal?.querySelector("[data-coffee-form-view]")
const coffeeQrView = coffeeModal?.querySelector("[data-coffee-qr-view]")
const coffeeAmount = document.getElementById("coffee-amount")
const coffeeMessage = document.getElementById("coffee-message")
const coffeeError = coffeeModal?.querySelector("[data-coffee-error]")
const coffeeQr = coffeeModal?.querySelector("[data-coffee-qr]")
const coffeeSummaryAmount = coffeeModal?.querySelector("[data-coffee-summary-amount]")
const coffeeSummaryMessage = coffeeModal?.querySelector("[data-coffee-summary-message]")
const coffeeAmountOptions = coffeeModal?.querySelectorAll("[data-coffee-amount]") || []
let coffeeOpener = null

function removeVietnameseAccents(value) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .replace(/\s+/g, " ")
    .trim()
}

function showCoffeeForm() {
  if (coffeeFormView) coffeeFormView.hidden = false
  if (coffeeQrView) coffeeQrView.hidden = true
  if (coffeeError) coffeeError.textContent = ""
}

function openCoffeeModal(opener) {
  if (!coffeeModal) return
  coffeeOpener = opener
  showCoffeeForm()
  coffeeModal.classList.add("open")
  coffeeModal.setAttribute("aria-hidden", "false")
  document.body.classList.add("modal-open")
  window.setTimeout(() => coffeeAmount?.focus(), 50)
  if (typeof gtag === 'function') {
    gtag('event', 'click_coffee_open')
  }
}

function closeCoffeeModal() {
  if (!coffeeModal) return
  coffeeModal.classList.remove("open")
  coffeeModal.setAttribute("aria-hidden", "true")
  document.body.classList.remove("modal-open")
  coffeeOpener?.focus()
}

document.querySelectorAll("[data-coffee-open]").forEach((button) => {
  button.addEventListener("click", () => openCoffeeModal(button))
})

document.querySelectorAll("[data-coffee-close]").forEach((button) => {
  button.addEventListener("click", closeCoffeeModal)
})

coffeeModal?.querySelector("[data-coffee-back]")?.addEventListener("click", () => {
  showCoffeeForm()
  coffeeAmount?.focus()
})

function updateCoffeeAmountSelection(amount) {
  coffeeAmountOptions.forEach((button) => {
    button.classList.toggle("active", Number(button.dataset.coffeeAmount) === amount)
  })
}

coffeeAmountOptions.forEach((button) => {
  button.addEventListener("click", () => {
    const amount = Number(button.dataset.coffeeAmount)
    if (coffeeAmount) coffeeAmount.value = String(amount)
    updateCoffeeAmountSelection(amount)
    if (coffeeError) coffeeError.textContent = ""
  })
})

coffeeAmount?.addEventListener("input", () => {
  updateCoffeeAmountSelection(Number(coffeeAmount.value))
  if (coffeeError) coffeeError.textContent = ""
})

coffeeForm?.addEventListener("submit", (event) => {
  event.preventDefault()

  const amount = Number.parseInt(coffeeAmount?.value || "50000", 10)
  const description = removeVietnameseAccents(coffeeMessage?.value || "") || "Ung ho Shotly"

  if (!Number.isFinite(amount) || amount < 5000) {
    if (coffeeError) {
      coffeeError.textContent = document.documentElement.lang === "vi"
        ? "Vui lòng nhập số tiền tối thiểu 5.000 VND."
        : "Please enter an amount of at least 5,000 VND."
    }
    coffeeAmount?.focus()
    return
  }

  const qrUrl = `https://qr.sepay.vn/img?acc=692696969&bank=MB&amount=${amount}&des=${encodeURIComponent(description)}`
  if (coffeeQr) coffeeQr.src = qrUrl
  if (coffeeSummaryAmount) coffeeSummaryAmount.textContent = `${amount.toLocaleString("vi-VN")} VND`
  if (coffeeSummaryMessage) coffeeSummaryMessage.textContent = description
  if (coffeeError) coffeeError.textContent = ""
  if (coffeeFormView) coffeeFormView.hidden = true
  if (coffeeQrView) coffeeQrView.hidden = false
  coffeeModal?.querySelector("[data-coffee-back]")?.focus()

  if (typeof gtag === 'function') {
    gtag('event', 'click_coffee_submit', {
      'amount': amount,
      'message': description
    })
  }
})

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && coffeeModal?.classList.contains("open")) {
    closeCoffeeModal()
  }
})

// Track download button clicks
document.querySelectorAll('a[download]').forEach((link) => {
  link.addEventListener('click', () => {
    if (typeof gtag === 'function') {
      gtag('event', 'click_download', {
        'file_name': link.getAttribute('href')
      })
    }
  })
})

window.addEventListener("scroll", updateHeader, { passive: true })
updateHeader()
