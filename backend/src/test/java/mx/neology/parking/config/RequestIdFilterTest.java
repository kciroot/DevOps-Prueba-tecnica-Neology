package mx.neology.parking.config;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class RequestIdFilterTest {

    private final RequestIdFilter filter = new RequestIdFilter();

    @Test
    void propagaElRequestIdRecibidoEnMdcYRespuesta() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/neo/vehiculos");
        request.addHeader(RequestIdFilter.HEADER, "3f2a9c1e0b7d4e5f8a6b1c2d3e4f5a6b");
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicReference<String> idDuranteLaPeticion = new AtomicReference<>();

        filter.doFilter(request, response,
                (req, res) -> idDuranteLaPeticion.set(MDC.get(RequestIdFilter.MDC_KEY)));

        assertThat(idDuranteLaPeticion.get()).isEqualTo("3f2a9c1e0b7d4e5f8a6b1c2d3e4f5a6b");
        assertThat(response.getHeader(RequestIdFilter.HEADER)).isEqualTo("3f2a9c1e0b7d4e5f8a6b1c2d3e4f5a6b");
        assertThat(MDC.get(RequestIdFilter.MDC_KEY)).as("el MDC se limpia al terminar").isNull();
    }

    @Test
    void reemplazaUnRequestIdInseguroOAusente() {
        assertThat(RequestIdFilter.resolveRequestId("abc\n{\"inyectado\":true}"))
                .doesNotContain("\n")
                .hasSize(36);
        assertThat(RequestIdFilter.resolveRequestId(null)).hasSize(36);
    }
}
